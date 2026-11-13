#!/usr/bin/env bash
# 构建 fcitx5-zh-doctor 的 .deb
# 词库文本随包分发，安装时由 postinst 用目标机的 libime 编译，
# 从而避免 "Invalid pinyin version"。
set -euo pipefail
ulimit -c 0 2>/dev/null || true

PKG_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$PKG_DIR/.." && pwd)"

PKG="fcitx5-zh-doctor"
VERSION="${VERSION:-0.1.0}"
ARCH="${ARCH:-all}"

ZHWIKI_TAG="0.3.1"
ZHWIKI_DATE="20261018"
ZHWIKI_URL="https://github.com/felixonmars/fcitx5-pinyin-zhwiki/releases/download/${ZHWIKI_TAG}/zhwiki-${ZHWIKI_DATE}.dict.yaml"

WORK="$PKG_DIR/.cache"
TREE="$WORK/tree"
DIST="$ROOT/dist"
YAML="$WORK/zhwiki.yaml"
TXT="$WORK/zhwiki.txt"

log() { printf '==> %s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

for c in dpkg-deb xz python3 curl; do
  command -v "$c" >/dev/null 2>&1 || die "缺少命令: $c"
done

mkdir -p "$WORK" "$DIST"

if [[ ! -f "$YAML" ]]; then
  log "下载词库源（$(basename "$YAML")）"
  curl -fL --retry 3 --progress-bar -o "$YAML.part" "$ZHWIKI_URL"
  mv "$YAML.part" "$YAML"
fi

if [[ ! -f "$TXT" || "$TXT" -ot "$YAML" ]]; then
  log "转换词库"
  python3 "$PKG_DIR/convert-dict.py" "$YAML" "$TXT"
fi

log "组装 deb 目录树"
rm -rf "$TREE"
mkdir -p "$TREE/DEBIAN"
cp -a "$PKG_DIR/root/." "$TREE/"
cp -a "$ROOT/theme/Material-Color-green" "$TREE/usr/share/fcitx5/themes/" 2>/dev/null || {
  mkdir -p "$TREE/usr/share/fcitx5/themes"
  cp -a "$ROOT/theme/Material-Color-green" "$TREE/usr/share/fcitx5/themes/"
}

# 主题依赖的图片资源来自系统里的 material-color 或 default 主题
for asset in arrow.png radio.png; do
  for cand in "/usr/share/fcitx5/themes/Material-Color-blue/$asset" "/usr/share/fcitx5/themes/default/$asset"; do
    if [[ -f "$cand" ]]; then
      cp -f "$cand" "$TREE/usr/share/fcitx5/themes/Material-Color-green/$asset"
      break
    fi
  done
done

log "压缩词库文本"
mkdir -p "$TREE/usr/share/fcitx5-zh-doctor"
xz -9 -T0 -c "$TXT" > "$TREE/usr/share/fcitx5-zh-doctor/zhwiki.txt.xz"

DOC="$TREE/usr/share/doc/$PKG"
mkdir -p "$DOC"
for f in README.md LICENSE NOTICE; do
  [[ -f "$ROOT/$f" ]] && cp -f "$ROOT/$f" "$DOC/"
done

log "生成 control"
SIZE="$(du -sk --exclude=DEBIAN "$TREE" | cut -f1)"
sed -e "s|@VERSION@|$VERSION|g" -e "s|@SIZE@|$SIZE|g" \
  "$PKG_DIR/debian/control.in" > "$TREE/DEBIAN/control"
cp "$PKG_DIR/debian/conffiles" "$TREE/DEBIAN/conffiles"
install -m755 "$PKG_DIR/debian/postinst" "$TREE/DEBIAN/postinst"
install -m755 "$PKG_DIR/debian/postrm" "$TREE/DEBIAN/postrm"
find "$TREE" -type d -exec chmod 755 {} +

OUT="$DIST/${PKG}_${VERSION}_${ARCH}.deb"
log "打包 $OUT"
dpkg-deb --build --root-owner-group "$TREE" "$OUT" >/dev/null
dpkg-deb --info "$OUT" | sed -n '1,12p'
printf '\n产物: %s (%s)\n' "$OUT" "$(du -h "$OUT" | cut -f1)"
