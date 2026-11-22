#!/system/bin/sh
# ============================================================
#  真我 Neo8 振动增强模块 · 安装后验证
#  用法: su -c 'sh verify.sh'
#
#  ★ 刷完模块重启后，请尽快运行本脚本（5 分钟内），
#    否则内核环形日志会把开机的加载记录冲掉，导致无法确认。
#
#  判断原理：驱动加载 RAM 固件时会打印它自己算出的校验和
#      [haptic_hv]ram_load: check sum pass : 0x0F76
#  这个值等于模块里那个文件的校验和 → 证明驱动读的确实是替换后的文件。
#  这是唯一无法伪造的证据。
#
#  作者：谦谦TWT
# ============================================================

MOD=/data/adb/modules/vib_wave_boost
RAM_MOD=$MOD/odm/firmware/aw8697_haptic_170.bin
STEP_MOD=$MOD/odm/firmware/aw8697_stepable_regulate_RTP_105_174Hz.bin

PASS=0; BAD=0; UNK=0
pass() { echo "  [✓] $1"; PASS=$((PASS+1)); }
fail() { echo "  [✗] $1"; BAD=$((BAD+1)); }
unk()  { echo "  [?] $1"; UNK=$((UNK+1)); }
info() { echo "      $1"; }

cksum() { od -An -v -tu1 "$1" 2>/dev/null | awk '{for(i=1;i<=NF;i++){n++; if(n>2) s+=$i}} END{printf "%04X", s%65536}'; }

echo "============================================================"
echo " 真我 Neo8 振动增强模块 · 验证"
echo "============================================================"

# ---------- 1 ----------
echo; echo "[1] 模块安装状态"
if [ ! -d "$MOD" ]; then
  echo; echo "结论：未安装 —— 找不到 $MOD"; exit 1
fi
if [ -f "$MOD/disable" ]; then
  fail "模块被 disable 了，不会加载"; exit 1
elif [ -f "$MOD/remove" ]; then
  fail "模块被标记为 remove，下次开机会被删除"; exit 1
else
  pass "模块目录存在且已启用（$(grep '^name=' $MOD/module.prop 2>/dev/null | cut -d= -f2-)）"
fi

# ---------- 2 ----------
echo; echo "[2] overlay 挂载"
if mount 2>/dev/null | grep -q "KSU on /odm/firmware"; then
  pass "KSU overlay 已挂载到 /odm/firmware"
else
  fail "没有 overlay —— 模块文件没挂上去"
fi

# ---------- 3 RAM ----------
echo; echo "[3] RAM 波形固件（系统触摸 / 点击 / 长按）"
RAM_VERDICT=""
if [ -f "$RAM_MOD" ]; then
  MOD_CK=$(cksum "$RAM_MOD"); MOD_SZ=$(wc -c < "$RAM_MOD" | tr -d ' ')
  pass "模块文件 ${MOD_SZ} 字节，校验和 0x${MOD_CK}"

  # 3a. overlay 后是否真的是这份文件（辅助证据，不能证明驱动读到）
  LIVE=/odm/firmware/aw8697_haptic_170.bin
  if [ -f "$LIVE" ]; then
    LIVE_MD5=$(md5sum "$LIVE" | cut -d' ' -f1)
    MOD_MD5=$(md5sum "$RAM_MOD" | cut -d' ' -f1)
    if [ "$LIVE_MD5" = "$MOD_MD5" ]; then
      pass "overlay 后 /odm/firmware 内容 = 模块文件（替换成功）"
    else
      fail "overlay 后内容与模块文件不一致（$LIVE_MD5 / $MOD_MD5）"
    fi
  fi

  # 3b. 决定性证据：驱动自己算的校验和
  DMG_CK=$(dmesg 2>/dev/null | grep -o "ram_load: check sum pass : 0x[0-9a-fA-F]*" | tail -1 | grep -o "0x[0-9a-fA-F]*")
  if [ -z "$DMG_CK" ]; then
    unk "内核日志里没有 ram_load 记录，无法确认驱动是否加载"
    info "（开机久了会被日志冲掉。请重启后立刻再跑一次本脚本）"
    RAM_VERDICT=unknown
  else
    info "驱动加载时校验和：$DMG_CK"
    if [ "$(echo ${DMG_CK#0x} | tr 'A-F' 'a-f')" = "$(echo $MOD_CK | tr 'A-F' 'a-f')" ]; then
      pass "★ 校验和一致 —— 驱动加载的就是模块固件，已生效"
      RAM_VERDICT=ok
    else
      fail "校验和 0x${DMG_CK#0x} ≠ 模块 0x${MOD_CK} —— 驱动加载的不是这个文件"
      RAM_VERDICT=bad
    fi
  fi
else
  fail "模块里没有 RAM 固件（若只想增强 stepable，这里应为 fail 但不影响其它部分）"
  RAM_VERDICT=skip
fi

# ---------- 4 stepable ----------
echo; echo "[4] stepable 模板（QS 滑块 / 键盘 / 无级强度）"
STEP_VERDICT=""
if [ -f "$STEP_MOD" ]; then
  STEP_SZ=$(wc -c < "$STEP_MOD" | tr -d ' ')
  STEP_PEAK=$(od -An -v -tu1 "$STEP_MOD" | awk '{for(i=1;i<=NF;i++){v=$i; if(v>127)v=256-v; if(v>m)m=v}} END{print m}')
  pass "模块文件 ${STEP_SZ} 字节，峰值 ${STEP_PEAK}（原厂是 12）"

  RTP_SZ=$(dmesg 2>/dev/null | grep -o "aw8697_stepable_regulate_RTP_105[^]]*\] size = [0-9]*bytes" | tail -1 | grep -o "size = [0-9]*" | grep -o "[0-9]*")
  if [ -n "$RTP_SZ" ]; then
    info "驱动加载时读到 ${RTP_SZ} 字节"
    if [ "$RTP_SZ" = "$STEP_SZ" ]; then
      pass "★ 尺寸一致 —— 驱动读的就是模块这份"
      STEP_VERDICT=ok
    else
      fail "尺寸不符（驱动 ${RTP_SZ} / 模块 ${STEP_SZ}）"
      STEP_VERDICT=bad
    fi
  else
    unk "日志里还没有 stepable 加载记录"
    info "（拉一下 QS 音量滑块触发一次，再跑本脚本）"
    STEP_VERDICT=unknown
  fi
else
  info "模块里没有 stepable（只增强 RAM 波形时是正常的）"
  STEP_VERDICT=skip
fi

# ---------- 5 故障 ----------
echo; echo "[5] 故障检查"
ZERO=$(dmesg 2>/dev/null | grep -c "haptic_hv.*buf_len = 0")
if [ "$ZERO" -eq 0 ]; then
  pass "没有 buf_len = 0 刷屏（SELinux 拦截固件的典型症状）"
else
  fail "出现 ${ZERO} 次 buf_len = 0 —— 驱动拿不到波形数据，马达会没反应"
  info "检查 sepolicy.rule 是否生效 / post-fs-data.sh 的 chcon 是否成功"
fi

# ---------- 结论 ----------
echo
echo "============================================================"
if [ "$BAD" -gt 0 ]; then
  echo " 结论：未生效 ❌   （${BAD} 项异常，见上方 ✗）"
elif [ "$RAM_VERDICT" = "ok" ] || [ "$STEP_VERDICT" = "ok" ]; then
  if [ "$RAM_VERDICT" = "ok" ] && [ "$STEP_VERDICT" = "ok" ]; then
    echo " 结论：完全生效 ✅"
  else
    echo " 结论：已生效 ✅（另一路未确认）"
  fi
elif [ "$UNK" -gt 0 ]; then
  echo " 结论：文件已就位，但无法确认驱动加载 ⚠️"
  echo
  echo " 请重启，开机后 5 分钟内立刻再跑一次本脚本。"
  echo " 只有看到「校验和一致」才算真正确认。"
else
  echo " 结论：待确认 ⚠️"
fi
echo "============================================================"
echo
echo " 判据速查："
echo "   ✓ 通过 ${PASS} 项   ✗ 异常 ${BAD} 项   ? 未确认 ${UNK} 项"
echo
echo " 最近 3 条 haptic_hv 日志："
dmesg 2>/dev/null | grep "haptic_hv" | tail -3 | sed 's/^/   /'
