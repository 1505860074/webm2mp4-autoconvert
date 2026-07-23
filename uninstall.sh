#!/usr/bin/env bash
# ============================================================
#  一键卸载脚本：把 install.sh 装的东西干净地移除。
#
#  用法：
#     ./uninstall.sh                # 停用并删除服务+脚本（保留 GNOME 录屏设置）
#     ./uninstall.sh --reset-gnome  # 顺便把 GNOME 录屏时长/快捷键恢复成系统默认
#
#  注意：不会删除你 ~/Videos 里的任何视频文件，请放心。
# ============================================================
set -euo pipefail

step() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
info() { printf '    %s\n' "$*"; }

UNIT_DST="$HOME/.config/systemd/user/webm2mp4.service"
SCRIPT_DST="$HOME/.local/bin/webm2mp4-watch.sh"

# 解析参数：判断用户有没有传 --reset-gnome
RESET_GNOME=0
for arg in "$@"; do
    [ "$arg" = "--reset-gnome" ] && RESET_GNOME=1
done

step "步骤 1：停止并禁用服务"
# 下面几条都加了 “|| true”，意思是“即使这条命令失败（比如服务本来就不存在）也不要中断脚本”。
systemctl --user stop webm2mp4.service 2>/dev/null || true
systemctl --user disable webm2mp4.service 2>/dev/null || true
info "服务已停止并取消开机自启。"

step "步骤 2：删除已安装的文件"
rm -f "$UNIT_DST"  && info "已删除服务文件：$UNIT_DST"
rm -f "$SCRIPT_DST" && info "已删除脚本文件：$SCRIPT_DST"
systemctl --user daemon-reload   # 让 systemd 忘掉刚删掉的服务

step "步骤 3：GNOME 录屏设置"
if [ "$RESET_GNOME" = "1" ]; then
    if command -v gsettings >/dev/null 2>&1; then
        # reset 会把该项恢复成系统默认值。
        gsettings reset org.gnome.settings-daemon.plugins.media-keys max-screencast-length || true
        gsettings reset org.gnome.settings-daemon.plugins.media-keys screencast || true
        info "已把最长录屏时长、录屏快捷键恢复为系统默认。"
    else
        info "环境里没有 gsettings，跳过。"
    fi
else
    info "保留 GNOME 录屏设置未改（如需恢复默认，重跑： ./uninstall.sh --reset-gnome）"
fi

step "卸载完成 ✅"
info "你的视频文件（~/Videos）完全没动。"
