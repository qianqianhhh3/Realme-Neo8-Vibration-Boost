#!/system/bin/sh
# ============================================================
#  post-fs-data: 确保 /odm/firmware 下的两个波形文件被替换
#
#  优先依赖 KSU overlay；若 overlay 未生效（部分 KSU 分支不支持 /odm），
#  退化为 bind mount 强制覆盖。
#
#  时序：驱动在开机约 8.8 秒加载固件，本脚本在其之前执行。
#
#  作者：谦谦TWT
# ============================================================

MODDIR=${0%/*}
SRC="$MODDIR/odm/firmware"
DST=/odm/firmware
LOG=/data/local/tmp/vib_boost_boot.log

: > "$LOG"
echo "[$(date +%H:%M:%S)] post-fs-data start" >> "$LOG"

# 等待 /odm 就绪（最多 10 秒）
i=0
while [ $i -lt 40 ]; do
  [ -f "$DST/aw8697_haptic_170.bin" ] && break
  sleep 0.25
  i=$((i+1))
done
echo "waited $i ticks for $DST" >> "$LOG"

apply_one() {
  f="$1"
  S="$SRC/$f"
  D="$DST/$f"
  [ -f "$S" ] || { echo "  skip $f (no module file)" >> "$LOG"; return; }
  [ -f "$D" ] || { echo "  skip $f (no target)" >> "$LOG"; return; }

  # 先给源文件打上 vendor_file 标签（/data 可写，这里能改）
  # bind mount 后目标会继承源文件的 context，ueventd 才能读
  chcon u:object_r:vendor_file:s0 "$S" 2>>"$LOG"

  A=$(md5sum "$D" 2>/dev/null | cut -d' ' -f1)
  B=$(md5sum "$S" 2>/dev/null | cut -d' ' -f1)
  if [ "$A" = "$B" ]; then
    echo "  $f: overlay already active" >> "$LOG"
  else
    if mount --bind "$S" "$D" 2>>"$LOG"; then
      echo "  $f: bind mounted" >> "$LOG"
      # 挂载点上再尝试一次（overlay 场景下可能允许）
      chcon u:object_r:vendor_file:s0 "$D" 2>/dev/null
    else
      echo "  $f: bind mount FAILED" >> "$LOG"
    fi
  fi
}

apply_one aw8697_haptic_170.bin
apply_one aw8697_stepable_regulate_RTP_105_174Hz.bin

echo "[$(date +%H:%M:%S)] done" >> "$LOG"
