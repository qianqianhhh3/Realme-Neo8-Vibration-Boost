#!/system/bin/sh
# ============================================================
#  真我 Neo8 振动增强模块 · 验证
#
#  sh verify.sh      输出一行结论（WebUI 用，规避多行回传问题）
#  sh verify.sh -v   输出完整报告（终端用）
#
#  判据：驱动加载固件时自行计算的校验和
#    [haptic_hv]ram_load: check sum pass : 0x0F76
#  该值等于模块内文件的校验和 → 驱动加载的确实是替换后的文件。
#
#  请于重启后 5 分钟内执行，否则内核日志被覆盖会得到「无法确认」。
#
#  作者：谦谦TWT
# ============================================================

VERBOSE=0
[ "$1" = "-v" ] && VERBOSE=1

MOD=/data/adb/modules/vib_wave_boost
RAM_MOD=$MOD/odm/firmware/aw8697_haptic_170.bin
STEP_MOD=$MOD/odm/firmware/aw8697_stepable_regulate_RTP_105_174Hz.bin

BAD=""; INFO=""; RAMC=""; STEPC=""
say() { [ "$VERBOSE" = "1" ] && echo "$1"; }
bad() { BAD="$BAD $1"; say "  [X] $1"; }
ok()  { say "  [OK] $1"; }

cksum() { od -An -v -tu1 "$1" 2>/dev/null | awk '{for(i=1;i<=NF;i++){n++; if(n>2) s+=$i}} END{printf "%04X", s%65536}'; }

[ "$VERBOSE" = "1" ] && {
  echo "============================================================"
  echo " 真我 Neo8 振动增强模块 · 验证"
  echo "============================================================"
  echo
}

# ---- 1 模块状态 ----
if [ ! -d "$MOD" ]; then
  echo "[FAIL] 模块未安装"
  exit 1
fi
[ -f "$MOD/disable" ] && bad "模块被disable"
[ -f "$MOD/remove" ]  && bad "模块被标记删除"
say "[1] 模块状态: 已启用"

# ---- 2 overlay ----
OVL=$(mount 2>/dev/null | awk '$3=="/odm/firmware" && $5=="overlay"' | head -1)
if [ -n "$OVL" ]; then
  ok "overlay 已挂载"
else
  bad "overlay未挂载"
  say "  -> /odm/firmware 当前挂载: $(mount 2>/dev/null | awk '$3=="/odm/firmware"{print $5; exit}')"
  say "  -> 若为 erofs/只读，说明模块未被挂载。请确认：1) 已重启 2) 模块列表里已启用"
fi

# ---- 3 RAM 固件 ----
if [ -f "$RAM_MOD" ]; then
  MC=$(cksum "$RAM_MOD")
  LIVE=/odm/firmware/aw8697_haptic_170.bin
  if [ -f "$LIVE" ] && [ "$(md5sum $LIVE|cut -d' ' -f1)" != "$(md5sum $RAM_MOD|cut -d' ' -f1)" ]; then
    bad "overlay内容不符"
  fi
  DC=$(dmesg 2>/dev/null | grep -o "ram_load: check sum pass : 0x[0-9a-fA-F]*" | tail -1 | grep -o "0x[0-9a-fA-F]*")
  if [ -z "$DC" ]; then
    RAMC="?"
    say "  RAM: 模块 $MC / 驱动 未知（日志已覆盖）"
  else
    DCv=$(echo "${DC#0x}" | tr 'A-F' 'a-f')
    MCv=$(echo "$MC" | tr 'A-F' 'a-f')
    if [ "$DCv" = "$MCv" ]; then
      RAMC="OK"
      ok "RAM 校验和一致 $MC"
    else
      RAMC="X"
      bad "RAM校验和不符($DC/$MC)"
    fi
  fi
else
  RAMC="-" ; bad "缺RAM固件"
fi

# ---- 4 stepable ----
if [ -f "$STEP_MOD" ]; then
  SSZ=$(wc -c < "$STEP_MOD" | tr -d ' ')
  RSZ=$(dmesg 2>/dev/null | grep -o "aw8697_stepable_regulate_RTP_105[^]]*\] size = [0-9]*bytes" | tail -1 | grep -o "size = [0-9]*" | grep -o "[0-9]*")
  if [ -z "$RSZ" ]; then
    STEPC="?"
    say "  STEP: 模块 ${SSZ}B / 驱动 未记录"
  elif [ "$RSZ" = "$SSZ" ]; then
    STEPC="OK"
    ok "stepable 尺寸一致 ${SSZ}B"
  else
    STEPC="X"
    bad "stepable尺寸不符(${RSZ}/${SSZ})"
  fi
else
  STEPC="-" ; bad "缺stepable"
fi

# ---- 5 故障 ----
ZR=$(dmesg 2>/dev/null | grep -c "haptic_hv.*buf_len = 0")
[ "$ZR" -gt 0 ] && bad "buf_len=0($ZR次)"

# ---- 输出 ----
if [ "$VERBOSE" = "1" ]; then
  echo
  echo "============================================================"
  if [ -z "$BAD" ]; then
    [ "$RAMC" = "OK" ] && echo " 结论：已生效" || echo " 结论：文件已就位，但无法确认驱动加载（重启后立即再运行）"
  else
    echo " 结论：异常 ->$BAD"
  fi
  echo "============================================================"
else
  # WebUI 模式：单行纯 ASCII 输出，规避 ksu.exec 多行/中文回传问题
  if [ -n "$BAD" ]; then
    echo "FAIL | bad:$BAD | RAM=$RAMC STEP=$STEPC"
  elif [ "$RAMC" = "OK" ]; then
    echo "OK | active | RAM=$RAMC STEP=$STEPC | no fault"
  else
    echo "WAIT | no kernel log | reboot then retry within 5 min | RAM=$RAMC STEP=$STEPC"
  fi
fi
