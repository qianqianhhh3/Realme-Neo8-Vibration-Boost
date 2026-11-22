#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
真我 Neo8 振动增强 —— 本地生成器

不下载任何二进制，直接读你自己手机上的原厂固件，按参数生成增强版，
所以永远和你当前的系统版本匹配。

用法（手机 Termux 里 su 之后，或电脑上把文件拷出来跑）：
    python3 make_boost.py --out ./out

在手机上直接跑（需要 root）：
    su -c "python3 make_boost.py --out /sdcard/vib_boost"

作者：谦谦TWT    本脚本由 AI 协助编写
"""
import argparse, os, shutil, math, sys

RAM_SRC = "/odm/firmware/aw8697_haptic_170.bin"
STEP_SRC = "/odm/firmware/aw8697_stepable_regulate_RTP_105_174Hz.bin"

RAM_GAIN  = 1.85   # RAM 波形增益（1.35 偏轻 / 1.7 甜点 / 2.0+ 会爆音）
RAM_IDS   = [0, 1, 2, 3, 5]
STEP_GAIN = 11.0   # stepable 正弦放大（原厂峰值 12，满幅 127 → 上限约 10.6x）


def parse_ram(data):
    """返回 [(start_file, end_file), ...]"""
    if len(data) < 0x31:
        raise ValueError("固件太小，格式不对")
    start0 = (data[5] << 8) | data[6]
    starts, ends, pos = [start0], [], 0x07
    while pos + 1 <= 0x30:
        ends.append((data[pos] << 8) | data[pos + 1]); pos += 2
        if pos + 1 > 0x30:
            break
        starts.append((data[pos] << 8) | data[pos + 1]); pos += 2
    out = []
    for s, e in zip(starts, ends):
        sf, ef = s - 0x07FC, e - 0x07FC
        if 0 <= sf < len(data) and sf <= ef < len(data):
            out.append((sf, ef))
    return out


def ram_checksum_ok(data):
    return ((data[0] << 8) | data[1]) == (sum(data[2:]) & 0xFFFF)


def build_ram(data, gain, ids):
    wf = parse_ram(data)
    for idx in ids:
        if idx >= len(wf):
            continue
        s, e = wf[idx]
        seg = [b if b < 128 else b - 256 for b in data[s:e + 1]]
        new = [127 if v * gain > 127 else (-128 if v * gain < -128 else int(round(v * gain)))
               for v in seg]
        data[s:e + 1] = bytes((v + 256) % 256 for v in new)
    c = sum(data[2:]) & 0xFFFF
    data[0] = (c >> 8) & 0xFF
    data[1] = c & 0xFF
    return data, c


def build_step(data, gain):
    vals = [b if b < 128 else b - 256 for b in data]
    new = [127 if v * gain > 127 else (-128 if v * gain < -128 else int(round(v * gain)))
           for v in vals]
    return bytes((v + 256) % 256 for v in new), max(vals, key=abs), max(new, key=abs)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="./out", help="输出目录")
    ap.add_argument("--ram-gain", type=float, default=RAM_GAIN)
    ap.add_argument("--step-gain", type=float, default=STEP_GAIN)
    ap.add_argument("--ram-src", default=RAM_SRC)
    ap.add_argument("--step-src", default=STEP_SRC)
    a = ap.parse_args()

    os.makedirs(a.out, exist_ok=True)
    fw = os.path.join(a.out, "odm", "firmware")
    bk = os.path.join(a.out, "original_firmware")
    os.makedirs(fw, exist_ok=True)
    os.makedirs(bk, exist_ok=True)

    # --- RAM 固件 ---
    if os.path.exists(a.ram_src):
        raw = bytearray(open(a.ram_src, "rb").read())
        print("[RAM] %s  %d 字节" % (a.ram_src, len(raw)))
        print("[RAM] 原厂校验和 %s" % ("OK" if ram_checksum_ok(raw) else "不正常！"))
        wf = parse_ram(raw)
        print("[RAM] 解析出 %d 个波形: %s" % (len(wf), [e - s + 1 for s, e in wf]))
        shutil.copy(a.ram_src, os.path.join(bk, "aw8697_haptic_170.bin"))
        new, c = build_ram(bytearray(raw), a.ram_gain, RAM_IDS)
        open(os.path.join(fw, "aw8697_haptic_170.bin"), "wb").write(new)
        print("[RAM] 已生成，增益 %.2fx，新校验和 0x%04X" % (a.ram_gain, c))
    else:
        print("[RAM] 找不到 %s，跳过（可以只做 stepable）" % a.ram_src)

    # --- stepable ---
    if os.path.exists(a.step_src):
        raw = open(a.step_src, "rb").read()
        print("[STEP] %s  %d 字节" % (a.step_src, len(raw)))
        shutil.copy(a.step_src, os.path.join(bk, os.path.basename(a.step_src)))
        out, pk_old, pk_new = build_step(raw, a.step_gain)
        open(os.path.join(fw, os.path.basename(a.step_src)), "wb").write(out)
        print("[STEP] 已生成，增益 %.1fx，峰值 %d → %d" % (a.step_gain, pk_old, pk_new))
    else:
        print("[STEP] 找不到 %s，跳过" % a.step_src)

    print("\n完成。把 %s 里的内容覆盖到模块目录：" % a.out)
    print("  odm/firmware/       → /data/adb/modules/vib_wave_boost/odm/firmware/")
    print("  original_firmware/  → 留着回滚用")
    print("改完记得 chcon u:object_r:vendor_file:s0，然后重启。")


if __name__ == "__main__":
    main()
