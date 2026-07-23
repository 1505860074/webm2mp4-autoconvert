#!/usr/bin/env bash
# ↑ 这行叫“shebang”，告诉系统：用 bash 这个解释器来运行本文件。必须在第一行。

# ============================================================
#  作用：盯着录屏文件夹，发现新的 .webm 就自动转成 .mp4，
#        转完删掉原 .webm；并且只保留最近 N 天的视频。
# ============================================================

set -u   # 开启“严格模式”之一：用到没定义过的变量就立刻报错，避免手误写错变量名。

# ---------- 可调参数（用“变量”存起来，方便以后改） ----------
# 写法 ${A:-B} 的意思是：如果外面设置了变量 A 就用 A，否则用默认值 B。
# 这些默认值和 config.env 里的一致；实际运行时 systemd 会把 config.env 的值注入进来覆盖它们。
WATCH_DIR="${WATCH_DIR:-$HOME/Videos}"   # 要监控的文件夹（$HOME 就是你的家目录 /home/xyz）
INTERVAL="${INTERVAL:-5}"                # 每隔几秒检查一次
STABLE_AGE="${STABLE_AGE:-8}"            # 文件“几秒没变化”才算录制完成
DELETE_ORIGINAL="${DELETE_ORIGINAL:-1}" # 转换后是否删原 .webm：1=删，0=保留
RETENTION_DAYS="${RETENTION_DAYS:-7}"    # 视频只保留最近多少天，超过就删除
LOG="${LOG:-$HOME/.local/state/webm2mp4.log}"   # 日志文件放哪

mkdir -p "$(dirname "$LOG")"   # 确保日志文件所在的文件夹存在（-p：不存在就创建，已存在也不报错）
                               # dirname 会取出路径里“文件夹”那部分。

# 定义一个叫 log 的“小函数”，专门用来往日志里写一行带时间的记录。
log() {
    # printf 是格式化输出；'%s %s\n' 表示“字符串 空格 字符串 换行”。
    # $(date '+%F %T') 会得到形如 2026-07-04 15:30:00 的当前时间。
    # "$*" 是调用 log 时传进来的所有文字。 >>"$LOG" 表示“追加写入”日志文件。
    printf '%s %s\n' "$(date '+%F %T')" "$*" >>"$LOG"
}

log "服务启动：监控目录=$WATCH_DIR，间隔=${INTERVAL}秒，保留=${RETENTION_DAYS}天"

# ---------- 主循环：while true 表示“永远循环下去” ----------
while true; do

    # ===== 第一部分：把录完的 .webm 转成 .mp4 =====
    now=$(date +%s)   # 取“现在”的时间戳（从1970年至今的总秒数），后面用来算文件年龄。

    # for 循环：把 WATCH_DIR 里所有 .webm 文件挨个拿出来，每次赋值给变量 f。
    # 用引号包住路径能正确处理“文件名里带空格”的情况（你的录屏名字就带空格）。
    for f in "$WATCH_DIR"/*.webm; do

        # 如果文件夹里一个 .webm 都没有，f 会等于字面量 "*.webm"（并不真实存在）。
        # [ -e "$f" ] 判断“这个文件真的存在吗”，不存在就 continue（跳过，进入下一轮 for）。
        [ -e "$f" ] || continue

        # 算出对应的输出文件名：把结尾的 .webm 去掉，换成 .mp4。
        # ${f%.webm} 意思是“从 f 的末尾去掉 .webm”。
        out="${f%.webm}.mp4"

        # 如果 .mp4 已经存在，说明早就转过了，跳过。
        [ -e "$out" ] && continue

        # 读取这个 .webm 的“最后修改时间”（时间戳，单位秒）。stat -c %Y 就是干这个的。
        mtime=$(stat -c %Y "$f")

        # 文件年龄 = 现在 - 最后修改时间（单位：秒）。$(( ... )) 是做整数算术。
        age=$(( now - mtime ))

        # 如果年龄小于设定的 8 秒，说明文件可能还在被写入（你可能还在录），先跳过，下轮再看。
        # -lt 是 less than（小于）的意思。
        [ "$age" -lt "$STABLE_AGE" ] && continue

        # 走到这里：这是一个“录完了、还没转过”的文件。开始转换。
        log "开始转换：$f"

        # 调用 ffmpeg 做真正的格式转换：
        #   -y            : 若输出已存在则直接覆盖，不再交互询问
        #   -i "$f"       : 输入文件
        #   -c:v libx264  : 视频用 H.264 编码（mp4 常用、兼容性好）
        #   -crf 20       : 画质，数字越小越清晰（18~23常用），20已很清晰
        #   -preset fast  : 编码速度与压缩率的折中档位
        #   -c:a aac -b:a 192k : 音频转成 AAC、码率192k
        #   "$out"        : 输出文件
        #   >>"$LOG" 2>&1 : 把 ffmpeg 的正常输出和错误信息都追加进日志
        # if ...; then 表示“如果这条命令成功（退出码0）就执行 then 里的内容”。
        if ffmpeg -y -i "$f" -c:v libx264 -crf 20 -preset fast \
                  -c:a aac -b:a 192k "$out" >>"$LOG" 2>&1; then
            log "转换成功：$out"
            # 如果开关是1（要删原文件），就删掉原 .webm。
            # [ 条件 ] && 命令  的意思是：条件成立才执行后面的命令。
            [ "$DELETE_ORIGINAL" = "1" ] && rm -f "$f" && log "已删除源文件：$f"
        else
            # else：ffmpeg 失败了。
            log "转换失败：$f"
            rm -f "$out"   # 删掉可能只转了一半的残缺 .mp4，避免下次误以为“已转过”。
        fi

    done   # for 循环结束

    # ===== 第二部分：清理超过 N 天的老视频 =====
    # 【重要开关】只有 RETENTION_DAYS 是“正整数”时才执行清理。
    #   若 RETENTION_DAYS<=0（比如默认的 0），就整段跳过，永不自动删除文件。
    #   -gt 是 greater than（大于）。这样把 0 当成“关闭清理”，避免误删。
    if [ "$RETENTION_DAYS" -gt 0 ]; then
        now=$(date +%s)   # 重新取一次当前时间

        # 把 .mp4 和 .webm 都纳入清理范围。这里列了两种后缀，for 会依次遍历它们匹配到的所有文件。
        for f in "$WATCH_DIR"/*.mp4 "$WATCH_DIR"/*.webm; do
            [ -e "$f" ] || continue                  # 同样，先确认文件真实存在
            mtime=$(stat -c %Y "$f")                 # 该文件最后修改时间
            age_days=$(( (now - mtime) / 86400 ))    # 换算成“天”。86400 = 一天的总秒数（24*60*60）
            # 如果年龄 >= 保留天数，就删除。-ge 是 greater or equal（大于等于）。
            if [ "$age_days" -ge "$RETENTION_DAYS" ]; then
                rm -f "$f"
                log "清理旧视频（${age_days}天前）：$f"
            fi
        done
    fi

    # ===== 睡一会儿，然后回到 while 顶部再来一轮 =====
    sleep "$INTERVAL"   # 暂停 INTERVAL 秒，避免一直空转占用CPU。

done
