# webm2mp4-autoconvert

在一台新机器上**一键还原**「快捷键快速录屏 → 自动转 mp4」这套工作流。

---

## 这套东西解决什么问题？

GNOME 桌面自带录屏功能（快捷键 `Ctrl+Shift+Alt+R`），但它**只能输出 `.webm` 格式**，兼容性不如 `.mp4`。这个项目补上最后一块拼图：一个常驻后台的小脚本盯着录屏文件夹，录完就自动用 ffmpeg 转成 mp4。

完整闭环：

```
Ctrl+Shift+Alt+R          →   GNOME 自带录屏（最长 30min）
（GNOME 内置 screencast）       只能输出 .webm，存到 ~/Videos
        │
        ▼
webm2mp4-watch.sh          →   每 5s 扫 ~/Videos，发现录完的 .webm
（systemd 常驻服务）              自动 ffmpeg 转成 .mp4
        ▼
   ~/Videos/*.mp4          →   通用格式，随手能用
```

---

## 目录结构

| 文件 | 作用 |
|---|---|
| `config.env` | **配置中心**。所有可调参数都在这，改这一个文件即可 |
| `webm2mp4-watch.sh` | 核心脚本：常驻循环，监控 + 转码 + （可选）清理 |
| `install.sh` | 一键安装：装依赖 → 装脚本 → 装服务 → 设 GNOME → 启动 |
| `uninstall.sh` | 一键卸载 |
| `README.md` | 就是本文件 |

---

## 快速开始（在新机器上）

新机器的**系统需与当前一致**（Ubuntu + GNOME 桌面，用户名 `xyz`）。把整个文件夹拷到 `/home/xyz/` 下，然后：

```bash
cd /home/xyz/webm2mp4-autoconvert
./install.sh
```

装完就生效了。录一段屏（`Ctrl+Shift+Alt+R` 开始/停止），几秒后 `~/Videos` 里就会多出对应的 `.mp4`。

> 首次运行 `install.sh` 若机器没装 ffmpeg，会用 `apt` 自动安装，届时需要输入 sudo 密码。

---

## 配置说明（`config.env`）

改完任意参数后，**重跑 `./install.sh`** 即可让新配置生效。

| 参数 | 默认值 | 含义 |
|---|---|---|
| `WATCH_DIR` | `$HOME/Videos` | 监控哪个文件夹 |
| `INTERVAL` | `5` | 每隔几秒扫一次 |
| `STABLE_AGE` | `8` | 文件几秒没变化才算“录完”（防止转到一半） |
| `DELETE_ORIGINAL` | `0` | 转完是否删原 `.webm`：`1`=删，`0`=保留 |
| `RETENTION_DAYS` | `0` | 只保留最近几天视频：`0`=**永不自动删**，正整数=开启按天清理 |
| `MAX_SCREENCAST_LENGTH` | `1800` | GNOME 单次最长录屏秒数（1800=30min） |
| `SCREENCAST_SHORTCUT` | `['<Ctrl><Shift><Alt>R']` | 录屏开关快捷键 |

### ⚠️ 关于两个“会删文件”的开关

本项目**默认采用保守设置**（`DELETE_ORIGINAL=0`、`RETENTION_DAYS=0`），即：**不删原始 webm、不按天自动清理**，最大限度避免误删。

- 你**当前老机器**上其实是激进设置（转完删 webm、超 7 天自动清理）。如果新机器也想这样省空间，把 `config.env` 改成 `DELETE_ORIGINAL=1`、`RETENTION_DAYS=7` 再重装即可。
- 开启 `RETENTION_DAYS` 后，脚本会**删除 `WATCH_DIR` 里超过 N 天的 mp4 和 webm**。所以这个目录别放需要长期保存的视频。

---

## 常用运维命令

```bash
# 看服务状态
systemctl --user status webm2mp4.service

# 看实时日志（每次转换/删除都会记一行带时间戳的记录）
tail -f ~/.local/state/webm2mp4.log

# 临时停 / 起 / 重启
systemctl --user stop    webm2mp4.service
systemctl --user start   webm2mp4.service
systemctl --user restart webm2mp4.service

# 卸载（保留 GNOME 设置）
./uninstall.sh
# 卸载并把 GNOME 录屏设置也恢复默认
./uninstall.sh --reset-gnome
```

---

## 工作原理

- **为什么用 systemd 服务而不是 cron？** 因为要 5 秒粒度扫一次，而 cron 最小只能到 1 分钟。所以改用「一个 `while true` 永不退出的脚本 + systemd 托管」：脚本自己 `sleep 5` 控制节奏，systemd 负责开机自启（`WantedBy=default.target`）和崩溃自动重启（`Restart=on-failure`）。
- **参数怎么传给脚本？** `install.sh` 会把 `config.env` 里的值写进服务文件的 `Environment=` 行，脚本运行时从环境变量读取。所以“改配置”的正确姿势是改 `config.env` 后重跑 `install.sh`。
- **注销后还跑吗？** systemd 用户服务默认在你**注销登录后停止**。由于录屏本身就需要图形会话，通常没影响。若确实想让它在注销后继续跑：`sudo loginctl enable-linger xyz`。

---

## 故障排查

| 现象 | 排查 |
|---|---|
| 录完没生成 mp4 | 先看日志 `tail -n 50 ~/.local/state/webm2mp4.log`；确认 `~/Videos` 里确实有 `.webm` |
| 服务起不来 | `systemctl --user status webm2mp4.service` 看报错；确认 `~/.local/bin/webm2mp4-watch.sh` 有执行权限 |
| 快捷键/时长没生效 | 可能安装时不在图形会话里（gsettings 被跳过）。登录桌面后在桌面终端重跑 `./install.sh` |
| 想确认 GNOME 当前设置 | `gsettings get org.gnome.settings-daemon.plugins.media-keys max-screencast-length` |
