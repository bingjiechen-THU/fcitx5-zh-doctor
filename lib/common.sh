#!/usr/bin/env bash
# 共享工具函数，被 install.sh / uninstall.sh 引入

if [[ -t 1 ]]; then
  C_RED=$'\033[31m'; C_GRN=$'\033[32m'; C_YEL=$'\033[33m'
  C_BLU=$'\033[34m'; C_DIM=$'\033[2m'; C_RST=$'\033[0m'
else
  C_RED=; C_GRN=; C_YEL=; C_BLU=; C_DIM=; C_RST=
fi

log()  { printf '%s==>%s %s\n' "$C_BLU" "$C_RST" "$*"; }
ok()   { printf '%s ok %s %s\n' "$C_GRN" "$C_RST" "$*"; }
warn() { printf '%swarn%s %s\n' "$C_YEL" "$C_RST" "$*" >&2; }
die()  { printf '%sfail%s %s\n' "$C_RED" "$C_RST" "$*" >&2; exit 1; }

need_cmd() { command -v "$1" >/dev/null 2>&1 || die "缺少命令: $1"; }

pkg_installed() { dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q "install ok installed"; }

# 在 ini 文件根级别（第一个 [section] 之前）设置 key=value
set_ini() {
  local file="$1" key="$2" value="$3" tmp
  mkdir -p "$(dirname "$file")"
  touch "$file"
  tmp="$(mktemp)"
  {
    printf '%s=%s\n' "$key" "$value"
    grep -v -E "^[[:space:]]*${key}=" "$file" || true
  } > "$tmp"
  mv "$tmp" "$file"
}

# 字符串形式的 INI 值加引号
quote_value() { printf '"%s"' "$1"; }

run_sudo() {
  if [[ $EUID -eq 0 ]]; then
    "$@"
  else
    sudo "$@"
  fi
}

stop_fcitx5() {
  if pgrep -x fcitx5 >/dev/null 2>&1; then
    pkill -x fcitx5 2>/dev/null || true
    for _ in $(seq 1 20); do
      pgrep -x fcitx5 >/dev/null 2>&1 || break
      sleep 0.1
    done
  fi
}

start_fcitx5() {
  if ! pgrep -x fcitx5 >/dev/null 2>&1; then
    fcitx5 -d >/dev/null 2>&1 || warn "fcitx5 启动失败，重新登录后再试"
  fi
}
