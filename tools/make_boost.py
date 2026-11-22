#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
真我 Neo8 振动增强 —— 检查 + 生成（一个工具，两种用法）

    python3 make_boost.py --check          只看能不能用，不改任何东西
    python3 make_boost.py --out /sdcard/vib_boost    生成

为什么不直接比对 md5：md5 只能说明「和我这台一模一样」，说明不了「能用」。
真正决定安全的是文件结构——所以这里解析校验和、描述符表、波形边界，
结构合法就能安全放大，哪怕固件版本不同。

作者：谦谦TWT    本工具由 AI 协助编写
"""
import argparse, os, sys, math, shutil, subprocess

RAM_NAME  = "aw8697_haptic_170.bin"
STEP_NAME = "aw8697_stepable_regulate_RTP_105_174Hz.bin"
RAM_PATHS  = ["/odm/firmware/" + RAM_NAME,
              "/vendor/firmware/" + RAM_NAME]
STEP_PATHS = ["/odm/firmware/" + STEP_NAME,
              "/vendor/firmware/" + STEP_NAME]

RAM_GAIN_DEFAULT  = 1.85
STEP_GAIN_DEFAULT = 11.0


# ---------------------------------------------------------------- 工具函数
def find_file(paths, override=None):
    if override:
        return override if os.path.isfile(override) else None
    for p in paths:
        if os.path.isfile(p):
            return p
    return None


def has_overlay(mount_path="/odm/firmware"):
    """模块生效后 /odm/firmware 会被 KSU overlay 覆盖，读到的是改过的文件"""
    try:
        with open("/proc/mounts") as f:
            for line in f:
                parts = line.split()
                if len(parts) >= 3 and parts[1] == mount_path and parts[2] == "overlay":
                    return True
    except Exception:
        pass
    return False


def parse_ram(data):
    """返回 (waveforms, err)。waveforms = [(start, end), ...] 文件内偏移"""
    if len(data) < 0x31:
        return None, "文件太小（%d 字节），不是 RAM 固件格式" % len(data)
    if data[0x04] == 0 and data[0x05] == 0:
        return None, "头部全零，不是有效固件"

    start0 = (data[5] << 8) | data[6]
    starts, ends, pos = [start0], [], 0x07
    while pos + 1 <= 0x30:
        ends.append((data[pos] << 8) | data[pos + 1]); pos += 2
        if pos + 1 > 0x30:
            break
        starts.append((data[pos] << 8) | data[pos + 1]); pos += 2

    if not starts or not ends:
        return None, "描述符表为空"

    wf, bad = [], []
    for i, (s, e) in enumerate(zip(starts, ends)):
        sf, ef = s - 0x07FC, e - 0x07FC
        if sf < 0 or ef < sf or ef >= len(data):
            bad.append((i, sf, ef))
            continue
        wf.append((sf, ef))

    if bad:
        return wf, "有 %d 个波形的地址越界：%s（文件可能被截断或不是这个芯片的固件）" % (len(bad), bad[:3])
    return wf, None


def checksum_ok(data):
    return ((data[0] << 8) | data[1]) == (sum(data[2:]) & 0xFFFF)


def wave_stats(data, s, e):
    v = [b if b < 128 else b - 256 for b in data[s:e + 1]]
    if not v:
        return 0, 0.0, 0
    peak = max(abs(x) for x in v)
    rms = math.sqrt(sum(x * x for x in v) / len(v))
    active = sum(1 for x in v if x)
    return peak, rms, active


def build_ram(data, gain, ids):
    wf, err = parse_ram(data)
    if err:
        raise RuntimeError(err)
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


# ---------------------------------------------------------------- 检查
def do_check(ram_src, step_src):
    ok_all = True
    print("=" * 56)
    print(" 真我 Neo8 振动增强 · 兼容性检查")
    print("=" * 56)

    if has_overlay() and not (ram_src and step_src):
        print("\n⚠️  检测到 /odm/firmware 已被模块 overlay 覆盖。")
        print("    现在读到的是「改过之后」的文件，不是原厂。")
        print("    想看真实情况：先卸载模块并重启，或用 --ram-src 指定原厂备份。")
        print("    （下面显示的是当前生效的文件，仅供确认模块是否工作）")

    # --- RAM ---
    print("\n[RAM 波形固件]")
    ram_path = find_file(RAM_PATHS, ram_src)
    if not ram_path:
        print("  ✗ 找不到 %s" % RAM_NAME)
        ok_all = False
        ram_ok = False
    else:
        data = bytearray(open(ram_path, "rb").read())
        print("  文件: %s" % ram_path)
        print("  大小: %d 字节" % len(data))
        wf, err = parse_ram(data)
        if err:
            print("  ✗ 结构解析失败: %s" % err)
            ok_all = ram_ok = False
        else:
            print("  波形数: %d  尺寸: %s" % (len(wf), [e - s + 1 for s, e in wf]))
            ck = checksum_ok(data)
            print("  校验和: %s (记录 0x%04X / 实算 0x%04X)" %
                  ("✗ 不一致" if not ck else "✓ 通过",
                   (data[0] << 8) | data[1], sum(data[2:]) & 0xFFFF))
            if not ck:
                print("  ⚠️ 校验和不自洽 —— 文件可能被改过但没重算校验，驱动会拒绝加载")
            print("  各波形:")
            for i, (s, e) in enumerate(wf):
                pk, rms, act = wave_stats(data, s, e)
                flag = "  ← 会被增强" if i in (0, 1, 2, 3, 5) else ""
                print("    [%2d] %4dB  峰值%4d  RMS%6.1f  发声%3d%s" % (i, e - s + 1, pk, rms, act, flag))
            ram_ok = True
        print("  结论: %s" % ("✓ 结构合法，可以安全增强" if ram_ok else "✗ 不要使用，请先反馈给作者"))
        ok_all = ok_all and ram_ok

    # --- stepable ---
    print("\n[stepable 模板]（QS 滑块 / 键盘 / 无级强度）")
    step_path = find_file(STEP_PATHS, step_src)
    if not step_path:
        print("  ✗ 找不到 %s" % STEP_NAME)
        step_ok = False
    else:
        raw = open(step_path, "rb").read()
        v = [b if b < 128 else b - 256 for b in raw]
        peak = max(abs(x) for x in v) if v else 0
        rms = math.sqrt(sum(x * x for x in v) / len(v)) if v else 0
        lead = next((i for i, x in enumerate(v) if x), 0)
        tail = len(v) - 1 - next((i for i in reversed(range(len(v))) if v[i]), len(v) - 1)
        print("  文件: %s" % step_path)
        print("  大小: %d 字节 (%.1fms @24kHz)" % (len(raw), len(raw) / 24.0))
        print("  峰值: %d   RMS: %.1f   前静音 %d 采样 / 后静音 %d 采样" % (peak, rms, lead, tail))
        step_ok = len(raw) > 100 and peak > 0
        if step_ok:
            print("  结论: ✓ 纯 int8 采样、无表结构，任何尺寸都能安全替换")
            need = 127.0 / peak if peak else 0
            print("        峰值 %d → 满幅 127 最多可放大 %.1fx（超过就只能削顶）" % (peak, need))
        else:
            print("  结论: ✗ 内容异常（全零或过短）")
        ok_all = ok_all and step_ok

    # --- 环境 ---
    print("\n[运行环境]")
    print("  芯片节点: %s" % ("✓ /dev/awinic_haptic" if os.path.exists("/dev/awinic_haptic") else "✗ 不存在"))
    print("  root: %s" % ("✓" if os.geteuid() == 0 else "✗ 请用 su 运行"))

    print("\n" + "=" * 56)
    if ok_all:
        print(" 结论：可以生成。执行：")
        print("   python3 make_boost.py --out /sdcard/vib_boost")
    else:
        print(" 结论：**不要生成**。上面有 ✗ 的项，先把信息反馈给作者。")
    print("=" * 56)
    return 0 if ok_all else 1


# ---------------------------------------------------------------- 生成
def do_build(out_dir, ram_gain, step_gain, ram_src, step_src, ids):
    fw = os.path.join(out_dir, "odm", "firmware")
    bk = os.path.join(out_dir, "original_firmware")
    os.makedirs(fw, exist_ok=True)
    os.makedirs(bk, exist_ok=True)
    made = []

    ram_path = find_file(RAM_PATHS, ram_src)
    if ram_path:
        raw = bytearray(open(ram_path, "rb").read())
        wf, err = parse_ram(raw)
        if err:
            print("✗ RAM 固件解析失败: %s —— 已跳过，不会生成" % err)
        else:
            shutil.copy(ram_path, os.path.join(bk, RAM_NAME))
            new, c = build_ram(bytearray(raw), ram_gain, ids)
            open(os.path.join(fw, RAM_NAME), "wb").write(new)
            print("✓ RAM 波形  增益 %.2fx  波形 %s  新校验和 0x%04X"
                  % (ram_gain, ids, c))
            made.append("odm/firmware/" + RAM_NAME)
            made.append("original_firmware/" + RAM_NAME)
    else:
        print("· 没找到 RAM 固件，跳过（只做 stepable）")

    step_path = find_file(STEP_PATHS, step_src)
    if step_path:
        raw = open(step_path, "rb").read()
        v = [b if b < 128 else b - 256 for b in raw]
        pk = max(abs(x) for x in v) if v else 0
        new = [127 if x * step_gain > 127 else (-128 if x * step_gain < -128 else int(round(x * step_gain)))
               for x in v]
        open(os.path.join(fw, STEP_NAME), "wb").write(bytes((x + 256) % 256 for x in new))
        shutil.copy(step_path, os.path.join(bk, STEP_NAME))
        print("✓ stepable  增益 %.1fx  峰值 %d → %d%s"
              % (step_gain, pk, max(abs(x) for x in new),
                 "（已触满幅，再多只能削顶）" if max(abs(x) for x in new) >= 127 else ""))
        made.append("odm/firmware/" + STEP_NAME)
        made.append("original_firmware/" + STEP_NAME)
    else:
        print("· 没找到 stepable，跳过")

    print("\n输出目录: %s" % os.path.abspath(out_dir))
    if subprocess.run(["id", "-u"], capture_output=True).stdout.strip() == b"0":
        print("\n下一步（手机上执行）：")
        print("  cp -r %s/odm /data/adb/modules/vib_wave_boost/" % os.path.abspath(out_dir))
        print("  chcon -R u:object_r:vendor_file:s0 /data/adb/modules/vib_wave_boost/odm/firmware/")
        print("  重启")
    else:
        print("\n把 odm/firmware/ 下的文件替换进手机模块目录，然后重启。")


def main():
    ap = argparse.ArgumentParser(
        description="真我 Neo8 振动增强 —— 检查与生成",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="示例:\n"
               "  python3 make_boost.py --check\n"
               "  python3 make_boost.py --out /sdcard/vib_boost\n"
               "  python3 make_boost.py --out ./out --ram-gain 1.7 --step-gain 8\n")
    ap.add_argument("--check", action="store_true", help="只检查，不生成")
    ap.add_argument("--out", help="生成到该目录")
    ap.add_argument("--ram-gain", type=float, default=RAM_GAIN_DEFAULT,
                    help="RAM 波形增益，默认 1.85（1.35 偏轻 / 1.7 甜点 / 2.0+ 爆音）")
    ap.add_argument("--step-gain", type=float, default=STEP_GAIN_DEFAULT,
                    help="stepable 增益，默认 11（原厂峰值 12，理论上限约 10.6x）")
    ap.add_argument("--ids", type=int, nargs="+", default=[0, 1, 2, 3, 5],
                    help="要增强的 RAM 波形索引，默认 0 1 2 3 5")
    ap.add_argument("--ram-src", help="指定 RAM 固件路径（默认从 /odm/firmware 找）")
    ap.add_argument("--step-src", help="指定 stepable 路径")
    a = ap.parse_args()

    if a.check:
        return do_check(a.ram_src, a.step_src)
    if a.out:
        do_build(a.out, a.ram_gain, a.step_gain, a.ram_src, a.step_src, a.ids)
        return 0
    ap.print_help()
    return 1


if __name__ == "__main__":
    sys.exit(main())
