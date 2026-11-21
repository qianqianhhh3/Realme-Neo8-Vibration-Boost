#!/system/bin/sh
# 振动强度增强（只在未设置时写入，尊重用户手动调整）
MODDIR=${0%/*}
i=0
while [ $i -lt 30 ]; do
  v=$(settings get system notification_stepless_vibration_intensity 2>/dev/null)
  [ -n "$v" ] && break
  sleep 1
  i=$((i+1))
done
v=$(settings get system notification_stepless_vibration_intensity 2>/dev/null)
[ "$v" = "null" ] && settings put system notification_stepless_vibration_intensity 2400
v=$(settings get system media_vibration_intensity 2>/dev/null)
[ "$v" = "null" ] && settings put system media_vibration_intensity 3
exit 0
