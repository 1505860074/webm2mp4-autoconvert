# 完整使用指南：从录屏到自动得到 MP4

本文手把手带你走一遍，从**在一台新电脑上安装**，到**日常录屏并拿到 mp4**，再到**排查问题 / 卸载**。面向初学者，尽量每一步都讲清楚。

> 适用环境：Ubuntu + GNOME 桌面（本项目最初在 Ubuntu 20.04 上使用）。

---

## 目录
1. [它到底做了什么（先理解闭环）](#1-它到底做了什么)
2. [第一次安装（软件部署）](#2-第一次安装软件部署)
3. [日常使用：录一段屏，自动得到 mp4](#3-日常使用录一段屏自动得到-mp4)
4. [怎么确认它在正常工作](#4-怎么确认它在正常工作)
5. [改配置（可选）](#5-改配置可选)
6. [常见问题排查](#6-常见问题排查)
7. [卸载](#7-卸载)

---

## 1. 它到底做了什么

GNOME 桌面自带一个录屏功能，按快捷键就能录，但它**只能存成 `.webm` 格式**。`.webm` 在很多播放器/剪辑软件里兼容性不好，我们通常想要 `.mp4`。

这套工具补上这一环：一个后台小程序一直盯着录屏文件夹，**你录完屏它就自动把 webm 转成 mp4**。整个链路：

```
① 按 Ctrl+Shift+Alt+R 开始录屏
        │  （GNOME 自带录屏，最长 30 分钟）
        ▼
② 再按一次 Ctrl+Shift+Alt+R 停止 → 生成 .webm，存到 ~/Videos
        │
        ▼
③ 后台服务每 5 秒扫一次 ~/Videos，发现录完的 .webm
        │  （自动调用 ffmpeg 转码）
        ▼
④ 同目录下出现同名 .mp4 —— 完成！
```

第 ③ 步的"后台服务"就是本项目安装的东西，它由 `systemd` 托管：**开机自动启动、崩溃自动重启**，你平时完全不用管。

---

## 2. 第一次安装（软件部署）

### 2.1 拿到项目文件

如果是从 GitHub 克隆：

```bash
cd ~
git clone git@github.com:1505860074/webm2mp4-autoconvert.git
cd webm2mp4-autoconvert
```

> 如果你已经把这个文件夹直接拷到了 `~/webm2mp4-autoconvert/`，跳过 clone，直接 `cd` 进去即可。

### 2.2 一键安装

```bash
./install.sh
```

这一条命令会自动完成 5 件事：

| 步骤 | 做了什么 |
|---|---|
| 1/5 | 检查 `ffmpeg`（转码引擎）。**没装就用 `apt` 自动装**，此时会要求你输入 sudo 密码 |
| 2/5 | 把核心脚本 `webm2mp4-watch.sh` 装到 `~/.local/bin/` |
| 3/5 | 生成 systemd 用户服务（参数取自 `config.env`） |
| 4/5 | 用 `gsettings` 把 GNOME 录屏设置写回系统（最长 30 分钟、快捷键 `Ctrl+Shift+Alt+R`） |
| 5/5 | 启动服务并设为开机自启，最后打印状态 |

看到最后打印出 `Active: active (running)` 就说明装好了。

> **名词解释**
> - **ffmpeg**：一个开源的音视频处理工具，格式转换就靠它。
> - **systemd 服务**：Linux 上管理"后台常驻程序"的标准机制，负责开机启动、崩溃重启。
> - **gsettings**：读写 GNOME 桌面各种设置的命令行工具。

### 2.3 （可选）注销后仍保持运行

systemd 用户服务默认在你**注销登录后会停止**。因为录屏本身也需要你登录着图形界面，所以一般没影响。若你确实想让它注销后仍运行：

```bash
sudo loginctl enable-linger $USER
```

---

## 3. 日常使用：录一段屏，自动得到 mp4

装好之后，日常就三步，非常简单：

1. **开始录屏**：按 `Ctrl + Shift + Alt + R`。屏幕右上角会出现一个红点，表示正在录。
2. **停止录屏**：再按一次 `Ctrl + Shift + Alt + R`。系统会在 `~/Videos/` 下生成一个 `.webm` 文件（文件名类似 `Screencast from 2026-07-23 21-00-00.webm`）。
3. **等几秒**：后台服务每 5 秒扫一次，确认文件"录完了（8 秒内没再变化）"后开始转码。转码耗时取决于视频长度，通常几秒到几十秒。完成后，同目录下就出现同名的 `.mp4`。

打开文件管理器进到 `~/Videos`，或用命令查看：

```bash
ls -lt ~/Videos | head
```

> 默认配置下（保守模式）**原始 `.webm` 会保留**、**不会自动删除旧视频**。所以你会同时看到 `.webm` 和 `.mp4`。想改成"转完删 webm / 定期清理"，见第 5 节。

---

## 4. 怎么确认它在正常工作

```bash
# 看服务是否在运行（应显示 active (running)）
systemctl --user status webm2mp4.service

# 看实时日志：每次转换/删除都会记一行带时间戳的记录
tail -f ~/.local/state/webm2mp4.log
```

`tail -f` 会持续刷新日志。你录一段屏，几秒后就能在这里看到 `开始转换...` → `转换成功...` 的记录。按 `Ctrl+C` 退出查看。

---

## 5. 改配置（可选）

所有可调项都在项目里的 `config.env`。**改完这个文件后，重跑 `./install.sh` 即可生效。**

| 参数 | 默认（保守） | 含义 |
|---|---|---|
| `WATCH_DIR` | `$HOME/Videos` | 监控哪个文件夹 |
| `INTERVAL` | `5` | 每隔几秒扫一次 |
| `STABLE_AGE` | `8` | 文件几秒没变化才算"录完" |
| `DELETE_ORIGINAL` | `0` | 转完是否删原 webm：`1`=删，`0`=保留 |
| `RETENTION_DAYS` | `0` | 保留最近几天：`0`=**永不自动删**，正整数=开启按天清理 |
| `MAX_SCREENCAST_LENGTH` | `1800` | 最长录屏秒数（1800=30 分钟） |
| `SCREENCAST_SHORTCUT` | `['<Ctrl><Shift><Alt>R']` | 录屏快捷键 |

**想省空间（激进模式）**：把 `DELETE_ORIGINAL=1`、`RETENTION_DAYS=7`，再 `./install.sh`。
效果 = 转完删原 webm，且自动删除 `~/Videos` 里超过 7 天的视频。

> ⚠️ 开启 `RETENTION_DAYS` 后会**自动删除**目录里的旧视频，别把需要长期保存的视频放这个目录。

---

## 6. 常见问题排查

| 现象 | 怎么办 |
|---|---|
| 录完没生成 mp4 | 先看日志 `tail -n 50 ~/.local/state/webm2mp4.log`；确认 `~/Videos` 里确实有 `.webm` |
| 服务起不来 | `systemctl --user status webm2mp4.service` 看报错；确认 `~/.local/bin/webm2mp4-watch.sh` 有执行权限（`ls -l` 应含 `x`） |
| 快捷键 / 录屏时长没生效 | 可能安装时不在图形会话里（gsettings 被跳过）。登录桌面后，在桌面终端里重跑 `./install.sh` |
| 想手动确认 GNOME 当前设置 | `gsettings get org.gnome.settings-daemon.plugins.media-keys max-screencast-length` |
| 提示找不到 ffmpeg | 手动装：`sudo apt-get update && sudo apt-get install -y ffmpeg` |

---

## 7. 卸载

```bash
cd ~/webm2mp4-autoconvert

# 停用并删除服务+脚本（保留 GNOME 录屏设置、保留你的视频）
./uninstall.sh

# 如果还想把 GNOME 录屏时长/快捷键也恢复成系统默认
./uninstall.sh --reset-gnome
```

卸载**不会删除 `~/Videos` 里的任何视频**，请放心。
