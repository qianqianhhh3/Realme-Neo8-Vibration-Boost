#!/system/bin/sh
# ============================================================
#  真我 Neo8 振动增强模块 · 验证
#
#  sh verify.sh      单行结论（WebUI 用）
#  sh verify.sh -v   完整报告
#
#  判据（按可靠性排序）：
#   1. 驱动加载固件时自行计算的校验和 == 模块文件校验和
#      [haptic_hv]ram_load: check sum pass : 0x0F76
#   2. /odm/firmware 下的文件内容 == 模块文件内容
#      不关心是 overlay 还是 bind mount —— 只要内容对就是替换成功
#
#  请于重启后 5 分钟内执行，否则内核日志被覆盖会无法确认。
#
#  作者：谦谦TWT
# ============================================================

VERBOSE=0
[ "$1" = "-v" ] && VERBOSE=1

MOD=/data/adb/modules/vib_wave_boost
RAM_MOD=$MOD/odm/firmware/aw8697_haptic_170.bin
STEP_MOD=$MOD/odm/firmware/aw8697_stepable_regulate_RTP_105_174Hz.bin
RAM_DST=/odm/firmware/aw8697_haptic_170.bin
STEP_DST=/odm/firmware/aw8697_stepable_regulate_RTP_105_174Hz.bin

BAD=""; RAMC=""; STEPC=""; FILEC=""
say() { [ "$VERBOSE" = "1" ] && echo "$1"; }
bad() { BAD="$BAD $1"; say "  [X] $1"; }
ok()  { say "  [OK] $1"; }

md5f() { md5sum "$1" 2>/dev/null | cut -d' ' -f1; }
cksum() { od -An -v -tu1 "$1" 2>/dev/null | awk '{for(i=1;i<=NF;i++){n++; if(n>2) s+=$i}} END{printf "%04X", s%65536}'; }

[ "$VERBOSE" = "1" ] && { echo "============================================================"; echo " 真我 Neo8 振动增强模块 · 验证"; echo "============================================================"; echo; }

# ---- 0 模块是否安装 ----
if [ ! -d "$MOD" ]; then
  [ "$VERBOSE" = "1" ] && echo "结论：模块未安装" || echo "FAIL | module not installed"
  exit 1
fi
[ -f "$MOD/disable" ] && bad "模块被disable"
[ -f "$MOD/remove" ]  && bad "模块被标记删除"
say "[0] 模块: 已安装"

# ---- 1 文件替换检查（overlay / bind mount 都算通过）----
say "[1] 文件替换"
if [ -f "$RAM_DST" ] && [ -f "$RAM_MOD" ]; then
  if [ "$(md5f $RAM_DST)" = "$(md5f $RAM_MOD)" ]; then
    ok "RAM 固件已替换"
  else
    bad "RAM固件未替换"
  fi
fi
if [ -f "$STEP_DST" ] && [ -f "$STEP_MOD" ]; then
  if [ "$(md5f $STEP_DST)" = "$(md5f $STEP_MOD)" ]; then
    ok "stepable 已替换"
  else
    bad "stepable未替换"
  fi
fi
# 挂载方式仅作诊断信息，不参与判据
MNT=$(mount 2>/dev/null | awk '$3=="/odm/firmware"{print $5; exit}')
FBM=$(mount 2>/dev/null | grep -c "^/dev.* /odm/firmware/aw8697_" )
say "    挂载方式: ${MNT:-无}${FBM:+，bind mount ${FBM} 个}"

# ---- 2 驱动加载的校验和（决定性证据）----
say "[2] 驱动加载校验"
if [ -f "$RAM_MOD" ]; then
  MC=$(cksum "$RAM_MOD")
  DC=$(dmesg 2>/dev/null | grep -o "ram_load: check sum pass : 0x[0-9a-fA-F]*" | tail -1 | grep -o "0x[0-9a-fA-F]*")
  if [ -z "$DC" ]; then
    RAMC="?"
    say "    RAM: 模块 $MC / 驱动 未记录（日志已覆盖）"
  elif [ "$(echo ${DC#0x}|tr 'A-F' 'a-f')" = "$(echo $MC|tr 'A-F' 'a-f')" ]; then
    RAMC="OK"; ok "RAM 校验和一致 $MC"
  else
    RAMC="X"; bad "RAM校验和不符($DC/$MC)"
  fi
fi

# ---- 3 stepable 加载记录 ----
if [ -f "$STEP_MOD" ]; then
  SSZ=$(wc -c < "$STEP_MOD" | tr -d ' ')
  RSZ=$(dmesg 2>/dev/null | grep -o "aw8697_stepable_regulate_RTP_105[^]]*\] size = [0-9]*bytes" | tail -1 | grep -o "size = [0-9]*" | grep -o "[0-9]*")
  if [ -z "$RSZ" ]; then
    STEPC="?"; say "    STEP: 模块 ${SSZ}B / 驱动 未记录"
  elif [ "$RSZ" = "$SSZ" ]; then
    STEPC="OK"; ok "stepable 尺寸一致 ${SSZ}B"
  else
    STEPC="X"; bad "stepable尺寸不符(${RSZ}/${SSZ})"
  fi
fi

# ---- 4 故障特征 ----
ZR=$(dmesg 2>/dev/null | grep -c "haptic_hv.*buf_len = 0")
[ "$ZR" -gt 0 ] && bad "buf_len=0($ZR次)"

# ---- 输出 ----
if [ "$VERBOSE" = "1" ]; then
  echo
  echo "============================================================"
  if [ -n "$BAD" ]; then
    echo " 结论：异常 ->$BAD"
  elif [ "$RAMC" = "OK" ]; then
    echo " 结论：已生效"
  else
    echo " 结论：文件已替换，但未取得驱动加载记录"
    echo "       请重启后 5 分钟内重试"
  fi
  echo "============================================================"
else
  if [ -n "$BAD" ]; then
    echo "FAIL | bad:$BAD | RAM=$RAMC STEP=$STEPC"
  elif [ "$RAMC" = "OK" ]; then
    echo "OK | active | RAM=$RAMC STEP=$STEPC | no fault"
  else
    echo "WAIT | file replaced, no kernel log | reboot then retry within 5 min | RAM=$RAMC STEP=$STEPC"
  fi
fi
