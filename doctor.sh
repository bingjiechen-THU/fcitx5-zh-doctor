#!/usr/bin/env bash
# fcitx5-zh-doctor: 自检并给出可执行的修复建议
set -uo pipefail
ulimit -c 0 2>/dev/null || true

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/lib/common.sh"

PASS=0
FAIL=0
WARN=0

pass() { PASS=$((PASS+1)); printf '  %s✓%s %s\n' "$C_GRN" "$C_RST" "$*"; }
warnc() { WARN=$((WARN+1)); printf '  %s!%s %s\n' "$C_YEL" "$C_RST" "$*"; }
failc() { FAIL=$((FAIL+1)); printf '  %s✗%s %s\n' "$C_RED" "$C_RST" "$*"; }
hint() { printf '      %s↳ %s%s\n' "$C_DIM" "$*" "$C_RST"; }

section() { printf '\n%s%s%s\n' "$C_BLU" "$1" "$C_RST"; }

check_system() {
  section "系统"
  printf '  %s\n' "$(lsb_release -ds 2>/dev/null || cat /etc/os-release 2>/dev/null | sed -n 's/^PRETTY_NAME=//p' | tr -d '"')"
  printf '  %s / %s\n' "${XDG_SESSION_TYPE:-未知}" "${XDG_CURRENT_DESKTOP:-未知}"
}

check_packages() {
  section "依赖包"
  local p
  for p in fcitx5 fcitx5-pinyin fcitx5-module-cloudpinyin libime-bin; do
    if pkg_installed "$p"; then
      pass "$p"
    else
      failc "$p 未安装"
      hint "sudo apt install $p"
    fi
  done
  if pkg_installed fonts-arphic-ukai; then
    pass "fonts-arphic-ukai（楷体）"
  else
    warnc "楷体字体未安装"
    hint "sudo apt install fonts-arphic-ukai"
  fi
}

check_running() {
  section "运行状态"
  if pgrep -x fcitx5 >/dev/null 2>&1; then
    pass "fcitx5 进程运行中"
  else
    failc "fcitx5 未运行"
    hint "fcitx5 -d"
  fi
  if [[ -f "$HOME/.xinputrc" ]] && grep -q "run_im fcitx5" "$HOME/.xinputrc"; then
    pass "~/.xinputrc 指向 fcitx5"
  else
    failc "~/.xinputrc 未指向 fcitx5"
    hint "im-config -n fcitx5"
  fi
  local bad=0 v
  for v in XMODIFIERS GTK_IM_MODULE QT_IM_MODULE; do
    local val="${!v:-}"
    if [[ "$val" == *fcitx* ]]; then
      pass "$v=$val"
    else
      bad=1
      warnc "$v=${val:-未设置}"
    fi
  done
  [[ $bad -eq 0 ]] || hint "重新登录后生效，或 source /etc/X11/xinit/xinputrc"
}

check_cloud() {
  section "云拼音"
  local conf="$HOME/.config/fcitx5/conf/pinyin.conf"
  local cconf="$HOME/.config/fcitx5/conf/cloudpinyin.conf"
  local backend

  if grep -qE "^CloudPinyinEnabled=(True|true|1)$" "$conf" 2>/dev/null; then
    pass "pinyin.conf 中云拼音已启用"
  else
    failc "CloudPinyinEnabled 未开启（模块装了但没生效）"
    hint "在 $conf 中设置 CloudPinyinEnabled=True"
  fi

  backend="$(sed -n 's/^Backend=//p' "$cconf" 2>/dev/null | head -1)"
  backend="${backend:-GoogleCN（默认）}"
  printf '  当前后端: %s\n' "$backend"

  local g
  g="$(curl -fsS -m 8 "https://www.google.cn/inputtools/request?ime=pinyin&text=zhongguo" 2>/dev/null | head -c 400)"
  if [[ "$g" == *中国* ]]; then
    pass "Google CN 接口可用"
  else
    warnc "Google CN 接口不可达"
    hint "公司网络或代理可能拦截了 www.google.cn"
  fi

  local b
  b="$(curl -fsS -m 8 "https://olime.baidu.com/py?rn=0&pn=1&ol=1&py=zhongguo" 2>/dev/null | head -c 400)"
  if [[ "$b" == *T* && "$b" == *result* ]]; then
    pass "百度 olime 接口可用"
  else
    warnc "百度 olime 接口已失效（fcitx5 5.0.x 的内置实现仍指向它）"
    hint "这就是为什么默认后端应改为 GoogleCN"
  fi

  if [[ "$backend" == *Baidu* ]]; then
    failc "后端设为百度，但该接口不可用"
    hint "在 $cconf 中改为 Backend=GoogleCN"
  fi
}

check_dict() {
  section "词库"
  local dir="$HOME/.local/share/fcitx5/pinyin/dictionaries"
  if [[ ! -d "$dir" ]]; then
    failc "词库目录不存在"
    hint "./install.sh"
    return
  fi
  local found=0 f tmp rc
  for f in "$dir"/*.dict; do
    [[ -e "$f" ]] || continue
    found=1
    tmp="$(mktemp -d)"
    libime_pinyindict -d "$f" "$tmp/d" >/dev/null 2>&1
    rc=$?
    rm -rf "$tmp"
    if [[ $rc -eq 0 ]]; then
      pass "$(basename "$f") 与 libime 兼容"
    else
      failc "$(basename "$f") 版本不兼容（Invalid pinyin version）"
      hint "./install.sh 会重新编译"
    fi
  done
  [[ $found -eq 1 ]] || { warnc "未发现额外词库"; hint "./install.sh"; }
}

check_ui() {
  section "界面"
  local conf="$HOME/.config/fcitx5/conf/classicui.conf"
  local theme
  theme="$(sed -n 's/^Theme=//p' "$conf" 2>/dev/null | head -1)"
  printf '  主题: %s\n' "${theme:-default}"
  printf '  字体: %s\n' "$(sed -n 's/^Font=//p' "$conf" 2>/dev/null | head -1)"
  if fc-list :lang=zh family 2>/dev/null | grep -qi "UKai CN"; then
    pass "AR PL UKai CN 可用"
  else
    warnc "未找到 AR PL UKai CN"
    hint "sudo apt install fonts-arphic-ukai"
  fi
  if [[ -n "$theme" && -d "$HOME/.local/share/fcitx5/themes/$theme" ]]; then
    pass "用户主题 $theme 存在"
  elif [[ -n "$theme" && -d "/usr/share/fcitx5/themes/$theme" ]]; then
    pass "系统主题 $theme 存在"
  elif [[ -n "$theme" ]]; then
    warnc "主题 $theme 不存在，会回退到 default"
  fi
}

main() {
  printf '\n%sfcitx5-zh-doctor%s\n' "$C_BLU" "$C_RST"
  check_system
  check_packages
  check_running
  check_cloud
  check_dict
  check_ui

  printf '\n%s结果%s: %s%d 通过%s, %s%d 警告%s, %s%d 失败%s\n\n' \
    "$C_BLU" "$C_RST" "$C_GRN" "$PASS" "$C_RST" \
    "$C_YEL" "$WARN" "$C_RST" "$C_RED" "$FAIL" "$C_RST"
  [[ $FAIL -eq 0 ]]
}

main "$@"
