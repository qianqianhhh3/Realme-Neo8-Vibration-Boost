#!/system/bin/sh
MODDIR=${0%/*}
F=/odm/firmware/aw8697_haptic_170.bin
for i in 1 2 3 4 5 6 7 8 9 10; do
  [ -f "$F" ] && break
  sleep 1
done
chcon u:object_r:vendor_file:s0 "$F" 2>/dev/null
