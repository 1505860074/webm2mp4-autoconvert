#!/usr/bin/env bash
# ============================================================
#  一键安装脚本：在一台新机器上，把“录屏 → 自动转 mp4”整套还原出来。
#
#  用法：
#     cd /home/xyz/webm2mp4-autoconvert
#     ./install.sh
#
#  它会依次做 5 件事：
#     1) 确保 ffmpeg 已安装（没有就用 apt 自动装，会问你要 sudo 密码）
#     2) 把核心脚本装到 ~/.local/bin/
#     3) 生成并安装 systemd 用户服务（参数取自 config.env）
#     4) 用 gsettings 把 GNOME 录屏设置（最长时长、快捷键）写回系统
#     5) 启动服务并设为开机自启，最后打印状态供你核对
#
#  可重复运行（幂等）：再跑一次只会用最新的 config.env 覆盖更新，不会重复堆叠。
# ============================================================

# set -e：任何一条命令出错就立即停止（避免带病继续）。
# set -u：用到未定义变量就报错。
# set -o pipefail：管道里任一环节失败，整条管道都算失败。
set -euo pipefail

# --- 定位“本脚本所在的文件夹”，这样不管你在哪里执行它都能找到同目录的其它文件 ---
# ${BASH_SOURCE[0]} 是本脚本自己的路径；dirname 取其所在目录；cd 进去再 pwd 得到绝对路径。
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- 读入配置中心 config.env，把里面的变量加载到当前 shell ---
# source（等同于点号 .）会“就地执行”那个文件，于是 WATCH_DIR 等变量就有值了。
# shellcheck source=config.env
source "$SCRIPT_DIR/config.env"

# 一个打印“步骤标题”的小函数，让输出更清楚。
step() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }   # \033[1;36m 是青色加粗，\033[0m 复位
info() { printf '    %s\n' "$*"; }

# 安装目标路径（都在“用户级”目录，不需要 root）
BIN_DIR="$HOME/.local/bin"
UNIT_DIR="$HOME/.config/systemd/user"
SCRIPT_DST="$BIN_DIR/webm2mp4-watch.sh"
UNIT_DST="$UNIT_DIR/webm2mp4.service"

echo "========================================================"
echo "  webm2mp4-autoconvert 安装程序"
echo "  监控目录 : $WATCH_DIR"
echo "  扫描间隔 : ${INTERVAL}s   稳定判定: ${STABLE_AGE}s"
echo "  删原webm : $DELETE_ORIGINAL(1=删/0=留)   保留天数: $RETENTION_DAYS(0=不清理)"
echo "  录屏时长 : ${MAX_SCREENCAST_LENGTH}s   快捷键: $SCREENCAST_SHORTCUT"
echo "========================================================"

# ---------- 步骤 1：确保 ffmpeg 存在 ----------
step "步骤 1/5：检查依赖 ffmpeg"
# command -v XXX 用来查“XXX 命令是否存在”，存在则打印其路径、返回成功。
if command -v ffmpeg >/dev/null 2>&1; then
    info "已安装：$(command -v ffmpeg)"
else
    info "未检测到 ffmpeg，准备用 apt 安装（需要 sudo 密码）……"
    sudo apt-get update
    sudo apt-get install -y ffmpeg
    info "ffmpeg 安装完成：$(command -v ffmpeg)"
fi

# ---------- 步骤 2：安装核心脚本 ----------
step "步骤 2/5：安装监控脚本到 $BIN_DIR"
mkdir -p "$BIN_DIR"                                   # 目录不存在就建
# install 命令：拷贝文件并同时设置权限。-m 755 表示“所有者可读写执行，其他人可读可执行”。
install -m 755 "$SCRIPT_DIR/webm2mp4-watch.sh" "$SCRIPT_DST"
info "已安装：$SCRIPT_DST"

# ---------- 步骤 3：生成并安装 systemd 服务 ----------
step "步骤 3/5：生成 systemd 用户服务"
mkdir -p "$UNIT_DIR"
# 用 heredoc（<<EOF ... EOF）把服务文件的内容“原样写出”，其中的 $变量 会被当前的值替换。
# Environment= 行把 config.env 的参数注入给脚本，这样改 config.env 重装即可改行为。
cat > "$UNIT_DST" <<EOF
[Unit]
Description=Auto-convert new GNOME screen recordings (.webm -> .mp4)

[Service]
Type=simple
Environment=WATCH_DIR=$WATCH_DIR
Environment=INTERVAL=$INTERVAL
Environment=STABLE_AGE=$STABLE_AGE
Environment=DELETE_ORIGINAL=$DELETE_ORIGINAL
Environment=RETENTION_DAYS=$RETENTION_DAYS
ExecStart=$SCRIPT_DST
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
EOF
info "已生成：$UNIT_DST"

# ---------- 步骤 4：写回 GNOME 录屏设置 ----------
step "步骤 4/5：应用 GNOME 录屏设置"
# gsettings 只有在有图形会话（GNOME + DBus）时才能用；命令行/SSH 环境可能没有。
# 所以先判断 gsettings 是否可用、对应 schema 是否存在，避免报错中断安装。
if command -v gsettings >/dev/null 2>&1 \
   && gsettings list-schemas 2>/dev/null | grep -q 'org.gnome.settings-daemon.plugins.media-keys'; then
    gsettings set org.gnome.settings-daemon.plugins.media-keys max-screencast-length "$MAX_SCREENCAST_LENGTH"
    gsettings set org.gnome.settings-daemon.plugins.media-keys screencast "$SCREENCAST_SHORTCUT"
    info "已设置最长录屏时长 = ${MAX_SCREENCAST_LENGTH}s，快捷键 = $SCREENCAST_SHORTCUT"
else
    info "⚠️ 当前环境没有可用的 GNOME gsettings（可能在纯命令行/SSH 里运行）。"
    info "   已跳过录屏设置。等你登录图形桌面后，再在桌面终端里重跑本脚本即可补上。"
fi

# ---------- 步骤 5：启动服务 + 设为开机自启 ----------
step "步骤 5/5：启动服务并设置开机自启"
systemctl --user daemon-reload          # 让 systemd 重新读取刚写入的服务文件
systemctl --user enable webm2mp4.service    # 开机自启
systemctl --user restart webm2mp4.service   # 立即（重）启动，确保用的是最新配置
info "服务已启动。"

# ---------- 收尾：打印状态供核对 ----------
step "安装完成 ✅ 当前状态："
systemctl --user --no-pager status webm2mp4.service | head -n 12 || true
echo
info "查看实时日志： tail -f ~/.local/state/webm2mp4.log"
info "改参数：编辑 config.env 后重跑 ./install.sh 即可生效"
info "卸载：   ./uninstall.sh"

# 温馨提示：默认 systemd 用户服务在“你注销登录后会停止”。
# 由于录屏本身也需要图形会话，这通常没影响。若你确实想让它在注销后仍运行，
# 可执行： sudo loginctl enable-linger $USER
echo
info "提示：如需注销后仍保持运行，可执行  sudo loginctl enable-linger $USER"
