#!/usr/bin/env bash
# fcitx5-zh-doctor installer
# 为 Ubuntu/Debian 上的 fcitx5 安装一套可用的中文输入预设：
#   - 依赖包
#   - 绿色楷体主题
#   - 云拼音（自动选可用的后端）
#   - 与本地 libime 版本匹配的 zh.wikipedia 词库
set -euo pipefail
ulimit -c 0 2>/dev/null || true

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/lib/common.sh"

VERSION="0.1.0"
ZHWIKI_TAG="0.3.1"
ZHWIKI_DATE="20261018"
ZHWIKI_URL="https://github.com/felixonmars/fcitx5-pinyin-zhwiki/releases/download/${ZHWIKI_TAG}/zhwiki-${ZHWIKI_DATE}.dict.yaml"

PACKAGES=(
  fcitx5
  fcitx5-chinese-addons
  fcitx5-pinyin
  fcitx5-module-cloudpinyin
  fcitx5-config-qt
  fcitx5-frontend-gtk3
  fcitx5-frontend-gtk4
  fcitx5-frontend-qt5
  libime-bin
  fonts-arphic-ukai
  curl
)

SKIP_DICT=0
SKIP_PACKAGES=0
ASSUME_YES=0

usage() {
  cat <<'USAGE'
用法: ./install.sh [选项]

  -y, --yes            不询问，直接安装
      --skip-packages  跳过依赖包安装
      --skip-dict      跳过词库编译
  -h, --help           显示帮助
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -y|--yes) ASSUME_YES=1 ;;
    --skip-packages) SKIP_PACKAGES=1 ;;
    --skip-dict) SKIP_DICT=1 ;;
    -h|--help) usage; exit 0 ;;
    *) usage; die "未知参数: $1" ;;
  esac
  shift
done

ensure_packages() {
  local missing=()
  local p
  for p in "${PACKAGES[@]}"; do
    pkg_installed "$p" || missing+=("$p")
  done
  if [[ ${#missing[@]} -eq 0 ]]; then
    ok "依赖包已全部安装"
    return
  fi

  log "需要安装: ${missing[*]}"
  if [[ $EUID -ne 0 && $ASSUME_YES -eq 0 ]]; then
    read -r -p "继续？会请求 sudo 权限 [Y/n] " reply
    [[ -z "${reply:-}" || "${reply,,}" == y* ]] || die "已取消"
  fi
  run_sudo env DEBIAN_FRONTEND=noninteractive apt-get update -qq || warn "apt update 失败，继续尝试安装"
  run_sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y "${missing[@]}"
}

install_theme() {
  local src="$SCRIPT_DIR/theme/Material-Color-green"
  local dst="$HOME/.local/share/fcitx5/themes/Material-Color-green"
  local assets=/usr/share/fcitx5/themes

  log "安装主题 -> $dst"
  mkdir -p "$dst"
  cp -f "$src/theme.conf" "$dst/theme.conf"
  # 箭头、单选图沿用系统主题自带的资源
  local f
  for f in arrow.png radio.png; do
    if [[ -f "$assets/Material-Color-blue/$f" ]]; then
      cp -f "$assets/Material-Color-blue/$f" "$dst/$f"
    elif [[ -f "$assets/default/$f" ]]; then
      cp -f "$assets/default/$f" "$dst/$f"
    fi
  done
}

write_configs() {
  local conf="$HOME/.config/fcitx5/conf"
  log "写入配置 -> $conf"

  set_ini "$conf/cloudpinyin.conf" "Backend" "GoogleCN"
  set_ini "$conf/cloudpinyin.conf" "MinimumPinyinLength" "3"

  set_ini "$conf/pinyin.conf" "CloudPinyinEnabled" "True"
  set_ini "$conf/pinyin.conf" "Prediction" "False"
  set_ini "$conf/pinyin.conf" "PageSize" "7"

  set_ini "$conf/classicui.conf" "Theme" "Material-Color-green"
  set_ini "$conf/classicui.conf" "Font" "$(quote_value "AR PL UKai CN 12")"
  set_ini "$conf/classicui.conf" "MenuFont" "$(quote_value "AR PL UKai CN 12")"
}

set_input_method() {
  if command -v im-config >/dev/null 2>&1; then
    log "设置 im-config -> fcitx5"
    im-config -n fcitx5 >/dev/null 2>&1 || warn "im-config 设置失败，可手动执行: im-config -n fcitx5"
    if ! grep -q "run_im fcitx5" "$HOME/.xinputrc" 2>/dev/null; then
      printf 'run_im fcitx5\n' > "$HOME/.xinputrc"
    fi
  else
    warn "未找到 im-config，请自行确保 XMODIFIERS=@im=fcitx"
  fi
}

dict_compatible() {
  local dict="$1" tmp
  [[ -f "$dict" ]] || return 1
  tmp="$(mktemp -d)"
  libime_pinyindict -d "$dict" "$tmp/dump.txt" >/dev/null 2>&1
  local rc=$?
  rm -rf "$tmp"
  return $rc
}

ensure_dict() {
  local dir="$HOME/.local/share/fcitx5/pinyin/dictionaries"
  local dict="$dir/zhwiki.dict"
  local system_dict="/usr/share/fcitx5/pinyin/dictionaries/zhwiki.dict"

  # deb 包已经装了系统级词库时不再重复安装，否则两份会被同时加载
  if dict_compatible "$system_dict"; then
    ok "已存在系统级词库（deb 安装），跳过"
    return
  fi
  local cache="${XDG_CACHE_HOME:-$HOME/.cache}/fcitx5-zh-doctor"
  local yaml="$cache/zhwiki.yaml"
  local txt="$cache/zhwiki.txt"

  if dict_compatible "$dict"; then
    ok "词库已就绪且与当前 libime 匹配"
    return
  fi
  if [[ -f "$dict" ]]; then
    local libime_ver
    libime_ver="$(dpkg-query -W -f='${Version}' libime-bin 2>/dev/null || echo 未知)"
    warn "现有词库与当前 libime（$libime_ver）不兼容，重新编译"
  fi

  need_cmd curl
  need_cmd python3
  need_cmd libime_pinyindict
  mkdir -p "$dir" "$cache"

  if [[ ! -f "$yaml" ]]; then
    log "下载词库源 zhwiki-$ZHWIKI_DATE（约 56MB）"
    curl -fL --retry 3 --progress-bar -o "$yaml.part" "$ZHWIKI_URL"
    mv "$yaml.part" "$yaml"
  fi

  log "转换为 libime 文本格式"
  python3 "$SCRIPT_DIR/packaging/convert-dict.py" "$yaml" "$txt"

  log "编译词库"
  libime_pinyindict "$txt" "$dict.tmp"
  mv "$dict.tmp" "$dict"
  chmod 644 "$dict"
  ok "词库已安装: $dict"
}

summary() {
  cat <<SUMMARY

$(ok "安装完成")

配置位置:
  ~/.config/fcitx5/conf/{classicui,cloudpinyin,pinyin}.conf
  ~/.local/share/fcitx5/themes/Material-Color-green/
  ~/.local/share/fcitx5/pinyin/dictionaries/zhwiki.dict

下一步:
  $([[ "${XMODIFIERS:-}" == "@im=fcitx" ]] && echo "已可用 Ctrl+Space 切换中英文" || echo "注销并重新登录，让输入法环境变量生效")

自检:
  ./doctor.sh
SUMMARY
}

main() {
  [[ $EUID -eq 0 ]] && die "请用普通用户运行（需要写入 ~/.config）。apt 需要时脚本会自己调用 sudo。"

  log "fcitx5-zh-doctor $VERSION"

  [[ $SKIP_PACKAGES -eq 1 ]] || ensure_packages
  [[ $SKIP_PACKAGES -eq 1 ]] || need_cmd libime_pinyindict

  stop_fcitx5
  install_theme
  write_configs
  set_input_method
  [[ $SKIP_DICT -eq 1 ]] || ensure_dict
  start_fcitx5
  summary
}

main "$@"
