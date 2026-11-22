#!/system/bin/sh
# ============================================================
#  AW8697 波形生成器（纯 shell，无需 python）
#  读本机原厂固件 → 按增益放大 → 重算校验和 → 输出
#
#  用法:
#    sh gen.sh                        # 默认参数
#    RAM_GAIN=1.7 sh gen.sh           # 自定义 RAM 增益
#    BUILD_STEP=1 sh gen.sh           # 额外按增益放大 stepable（会覆盖定制波形）
#    OUT=/sdcard/out sh gen.sh        # 自定义输出目录
#
#  作者：谦谦TWT
# ============================================================

RAM_SRC="${RAM_SRC:-/odm/firmware/aw8697_haptic_170.bin}"
STEP_SRC="${STEP_SRC:-/odm/firmware/aw8697_stepable_regulate_RTP_105_174Hz.bin}"
OUT="${OUT:-/sdcard/vib_boost}"
RAM_GAIN="${RAM_GAIN:-1.85}"
STEP_GAIN="${STEP_GAIN:-11.0}"
IDS="${IDS:-0 1 2 3 5}"

FW="$OUT/odm/firmware"
BK="$OUT/original_firmware"
mkdir -p "$FW" "$BK" || { echo "无法创建 $OUT"; exit 1; }

# ---------- RAM 波形固件 ----------
if [ -f "$RAM_SRC" ]; then
  echo "[RAM] 源: $RAM_SRC  ($(wc -c < "$RAM_SRC" | tr -d ' ') 字节)"
  echo "[RAM] 增益 $RAM_GAIN  波形索引: $IDS"

  od -An -v -tu1 "$RAM_SRC" | awk -v gain="$RAM_GAIN" -v ids="$IDS" '
  { for (i = 1; i <= NF; i++) b[++n] = $i }
  END {
    # 描述符表: 文件偏移 0x05 起，每 2 字节一个大端地址，交替 start/end
    starts[1] = b[6] * 256 + b[7]
    ns = 1; ne = 0; pos = 8
    while (pos + 1 <= 49) {
      ends[++ne] = b[pos] * 256 + b[pos+1]; pos += 2
      if (pos + 1 > 49) break
      starts[++ns] = b[pos] * 256 + b[pos+1]; pos += 2
    }
    split(ids, idarr, " ")
    for (k = 1; k <= length(idarr); k++) {
      idx = idarr[k] + 1
      if (idx > ne) continue
      fs = starts[idx] - 2044          # 0x07FC
      fe = ends[idx] - 2044
      if (fs < 0 || fe < fs || fe >= n) {
        printf "  [!] 波形 %d 地址越界，跳过\n", idarr[k] > "/dev/stderr"
        continue
      }
      for (p = fs + 1; p <= fe + 1; p++) {
        v = b[p]; if (v > 127) v -= 256
        x = v * gain
        if (x > 127) x = 127
        else if (x < -128) x = -128
        x = int(x + (x >= 0 ? 0.5 : -0.5))          # 四舍五入并取整
        b[p] = (x < 0) ? x + 256 : x
      }
      printf "  波形 %d: 偏移 %d~%d (%d 字节)\n", idarr[k], fs, fe, fe - fs + 1 > "/dev/stderr"
    }
    # 校验和 = sum(data[2:]) & 0xFFFF，大端写入前两字节
    sum = 0
    for (p = 3; p <= n; p++) sum += int(b[p])
    sum = sum % 65536
    b[1] = int(sum / 256); b[2] = sum % 256
    printf "  新校验和: 0x%04X\n", sum > "/dev/stderr"
    for (p = 1; p <= n; p++) printf "%c", int(b[p])
  }' > "$FW/aw8697_haptic_170.bin"

  if [ -s "$FW/aw8697_haptic_170.bin" ]; then
    SZ=$(wc -c < "$FW/aw8697_haptic_170.bin" | tr -d ' ')
    CK=$(od -An -v -tu1 "$FW/aw8697_haptic_170.bin" | awk '{for(i=1;i<=NF;i++){n++; if(n>2) s+=$i}} END{printf "%04X", s%65536}')
    echo "[RAM] 输出 $SZ 字节, 校验和 0x$CK"
    cp "$RAM_SRC" "$BK/aw8697_haptic_170.bin"
  else
    echo "[RAM] 生成失败"; rm -f "$FW/aw8697_haptic_170.bin"
  fi
else
  echo "[RAM] 找不到 $RAM_SRC，跳过"
fi

# ---------- stepable（默认跳过：模块内已预置定制波形，非等比放大产物）----------
if [ "${BUILD_STEP:-0}" != "1" ]; then
  echo "[STEP] 跳过（模块已预置 1084 采样的定制波形；如需覆盖请设 BUILD_STEP=1）"
elif [ -f "$STEP_SRC" ]; then
  echo "[STEP] 源: $STEP_SRC  ($(wc -c < "$STEP_SRC" | tr -d ' ') 字节)"
  od -An -v -tu1 "$STEP_SRC" | awk -v gain="$STEP_GAIN" '
  { for (i = 1; i <= NF; i++) b[++n] = $i }
  END {
    pk = 0
    for (p = 1; p <= n; p++) { v = b[p]; if (v > 127) v -= 256; if (v < 0) v = -v; if (v > pk) pk = v }
    for (p = 1; p <= n; p++) {
      v = b[p]; if (v > 127) v -= 256
      x = v * gain
      if (x > 127) x = 127
      else if (x < -128) x = -128
      x = int(x + (x >= 0 ? 0.5 : -0.5))          # 四舍五入并取整
      b[p] = (x < 0) ? x + 256 : x
    }
    npk = 0
    for (p = 1; p <= n; p++) { v = b[p]; if (v > 127) v -= 256; if (v < 0) v = -v; if (v > npk) npk = v }
    printf "  峰值 %d → %d%s\n", pk, npk, (npk >= 127 ? " (已触满幅)" : "") > "/dev/stderr"
    for (p = 1; p <= n; p++) printf "%c", int(b[p])
  }' > "$FW/aw8697_stepable_regulate_RTP_105_174Hz.bin"

  if [ -s "$FW/aw8697_stepable_regulate_RTP_105_174Hz.bin" ]; then
    echo "[STEP] 输出 $(wc -c < "$FW/aw8697_stepable_regulate_RTP_105_174Hz.bin" | tr -d ' ') 字节"
    cp "$STEP_SRC" "$BK/"
  else
    echo "[STEP] 生成失败"; rm -f "$FW/aw8697_stepable_regulate_RTP_105_174Hz.bin"
  fi
else
  echo "[STEP] 找不到 $STEP_SRC，跳过"
fi

echo
echo "输出: $OUT"
echo "  odm/firmware/      替换进模块目录"
echo "  original_firmware/ 原厂备份"
