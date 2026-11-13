#!/usr/bin/env bash
# 卸载 fcitx5-zh-doctor 写入的用户级内容（不动系统包）
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SCRIPT_DIR/lib/common.sh"

RESTORE_IM=0
[[ "${1:-}" == "--restore-im" ]] && RESTORE_IM=1

stop_fcitx5

log "删除用户主题"
rm -rf "$HOME/.local/share/fcitx5/themes/Material-Color-green"

log "删除编译的词库"
rm -f "$HOME/.local/share/fcitx5/pinyin/dictionaries/zhwiki.dict"

log "删除项目缓存"
rm -rf "${XDG_CACHE_HOME:-$HOME/.cache}/fcitx5-zh-doctor"

if [[ $RESTORE_IM -eq 1 ]] && command -v im-config >/dev/null 2>&1; then
  log "输入法框架切回自动检测"
  im-config -n auto >/dev/null 2>&1 || warn "im-config 回退失败，可手动执行: im-config -n auto"
fi

start_fcitx5
ok "已清理"
cat <<'MSG'

保留内容（按需手动删除）:
  ~/.config/fcitx5/conf/*.conf
重新登录后 ibus/自动检测生效。
MSG
