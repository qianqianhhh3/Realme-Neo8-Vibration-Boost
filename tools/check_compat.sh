#!/system/bin/sh
# 真我 Neo8 振动增强模块 —— 兼容性自检
# 用法: su -c 'sh check_compat.sh'

RAM=/odm/firmware/aw8697_haptic_170.bin
STEP=/odm/firmware/aw8697_stepable_regulate_RTP_105_174Hz.bin

echo "================ 兼容性自检 ================"
echo
echo "[1] RAM 波形固件"
if [ -f "$RAM" ]; then
  echo "    大小: $(wc -c < $RAM) 字节  (模块制作时: 4611)"
  echo "    md5 : $(md5sum $RAM | cut -d' ' -f1)"
  echo "    期望: 8bb3e6427579954b3e0848e8a463ce84"
  if [ "$(md5sum $RAM | cut -d' ' -f1)" = "8bb3e6427579954b3e0848e8a463ce84" ]; then
    echo "    ✅ 完全匹配，可以整套刷入"
  else
    echo "    ⚠️ 不匹配 —— 不要用模块里的 RAM 固件，"
    echo "       请用 make_boost.py 在本地生成，或只刷 stepable 部分"
  fi
else
  echo "    ❌ 文件不存在"
fi
echo
echo "[2] stepable 模板（QS 滑块 / 键盘）"
if [ -f "$STEP" ]; then
  echo "    大小: $(wc -c < $STEP) 字节  (模块制作时: 423)"
  echo "    md5 : $(md5sum $STEP | cut -d' ' -f1)"
  echo "    原厂: 50c4dc45edecbbe7ae369517d25ea4f3"
  SZ=$(wc -c < $STEP)
  if [ "$SZ" = "423" ]; then
    echo "    ✅ 大小一致，纯采样无表结构，可直接替换"
  else
    echo "    ⚠️ 大小不同，请用 make_boost.py 在本地生成"
  fi
else
  echo "    ❌ 文件不存在"
fi
echo
echo "[3] 芯片与驱动"
echo "    设备节点: $(ls -l /dev/awinic_haptic 2>/dev/null || echo 不存在)"
echo "    dmesg: $(dmesg | grep -m1 -oE '\[haptic_hv\].*' || echo 未找到 haptic_hv 日志)"
echo
echo "============================================"
