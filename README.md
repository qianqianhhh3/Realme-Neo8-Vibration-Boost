# 真我 Neo8 震动增强模块

> **本项目大量内容由 AI 生成。**
>
> 模块的代码、波形数据、逆向分析结论与本文档，绝大部分由 AI 助手（DeepSeek / 奶汐）在实机上边跑边写完成，人类主要承担提出方向、实际体感测试与决策。
> 波形参数是在这台机器上**反复重启实测**调出来的，不是理论推导。换机型请先读完「适用条件」。
> 使用风险自负，作者不对任何硬件损坏负责。

---

## 适用条件（⚠️ 必读）

```sh
su -c 'md5sum /odm/firmware/aw8697_haptic_170.bin'
```

必须等于 **`8bb3e6427579954b3e0848e8a463ce84`**。

不等说明固件版本不同，模块内的波形文件与你的机器不匹配，刷入后**可能导致马达完全不振动**（可回滚，但没必要踩）。

- 实测机型：realme Neo8 / RMX8899 / Android 17 / realmeUI 7.0
- 芯片：AW8697（AAC RichTap 方案，驱动 `haptic_hv`）
- 需要：KernelSU / ReSukiSU（模块依赖 overlay + sepolicy 注入）

## 效果

| 通道 | 文件 | 参数 | 体感 |
|---|---|---|---|
| 系统触摸 / 点击 / 长按 | `aw8697_haptic_170.bin`（RAM 波形表） | **1.85x** + 软削顶 | 更「实」更有分量 |
| QS 音量/亮度滑块、键盘、无级强度 | `aw8697_stepable_regulate_RTP_105_174Hz.bin` | 正弦 **11x**（纯净放大） | 更「足」，同时保持细腻 |
| 通知 / 媒体强度 | `service.sh` 写入 Settings | 通知 1800→2400、媒体 MEDIUM→HIGH | 通知 +33%，媒体 ×1.4 |

强度那两条**只在该项为空时写入**，你手动调过的值不会被覆盖。

## 安装

```text
ReSukiSU / KernelSU 管理器 → 模块 → 从本地安装 → 选择 zip → 重启
```

**必须重启**：波形是驱动 probe 时一次性烧进芯片 RAM 的，系统里没有任何热重载接口。

## 卸载

```sh
# 波形：删模块后重启，overlay 消失自动回原厂
su -c 'touch /data/adb/modules/vib_wave_boost/remove && reboot'

# 强度：手动清除
su -c 'settings delete system notification_stepless_vibration_intensity'
su -c 'settings delete system media_vibration_intensity'
```

仓库里 `original_firmware/` 是两个原厂 bin，可 `cp` 回模块目录替换。

## 调参刻度

实测出来的手感刻度，自己改波形时可直接参考：

| 通道 | 偏轻 | 甜点 | 红线 |
|---|---|---|---|
| RAM 波形 | 1.35x | 1.7 ~ 1.85x | **2.0x 以上 LRA 打到底，听到「噼」的爆音** |
| stepable | 原厂峰值 12（几乎没感觉） | 8 ~ 11x | 12×11=132 已触 int8 上限，再高只能削顶，会变「嗡嗡」粗糙 |

> **stepable 必须保持正弦。** 试过方波化：QS 滑块当场变成转子马达那种嗡嗡声，被用户打回。

## 原理

### 两条完全独立的通道

| 场景 | 证据 | 数据源 |
|---|---|---|
| 系统触摸 | 把 RAM 波形全置零 → 触摸彻底没声 | `aw8697_haptic_170.bin` 的 RAM 波形表 |
| 键盘 / QS 滑块 | RAM 全置零后键盘照响不误 | `aw8697_stepable_regulate_RTP_105_174Hz.bin`（RTP 流） |

驱动日志能直接看出走哪条：

```
[haptic_hv]rtp_play: buf_len = 415   ← stepable 去头 8 字节（423-8）
[haptic_hv]rtp_play: buf_len = 349   ← RAM 波形 [0]
```

### 为什么原厂 QS 滑块几乎没振动

`stepable_regulate_RTP_105` 原厂峰值只有 **12**，不到 int8 满幅（127）的 10%。
而无级强度模式下，系统只是在这个模板上做振幅缩放——**天花板从源头就被压死了**。

### 文件格式

```
aw8697_haptic_170.bin (4611B)
  0x00-0x01  16bit 校验和（大端）= sum(data[2:]) & 0xFFFF
  0x02-0x03  base address（0x0800）
  0x04       version
  0x05-0x30  描述符表，每个波形的 RAM 起止地址（大端）
  0x31+      波形数据，int8 有符号采样 @24kHz
  文件偏移 = RAM 地址 - 0x07FC

  11 个波形：[0]349B  [1][3][5]415B  [2]960B  [9]344B ...

aw8697_stepable_regulate_RTP_105_174Hz.bin (423B)
  裸 int8 采样，无头。39~367 是发声区，其余静音。原厂峰值 12。
```

改完**必须重算校验和**，否则驱动直接 `check sum fail` 拒绝加载。


## 固件版本不一致怎么办

不同批次的机器 / 不同系统版本，`stepable` 文件可能大小不同（见过 331 和 423 两种）。

**能直接替换吗？**

- `stepable_...105...bin` 是**裸 int8 采样、无头部无地址表**，驱动按实际文件长度读取
  （日志里 `rtp file:[...] size = NNNbytes`）。所以**只要内容是 int8 采样，多大的都能用**，
  大小只影响振动时长。
- `aw8697_haptic_170.bin` 有**描述符表 + 校验和**，地址表错一位波形就错位，
  **必须 md5 完全一致**才安全。

**推荐做法：在你的机器上自己生成**

```sh
# 先自检
su -c 'sh tools/check_compat.sh'

# 再本地生成（读你自己的原厂文件，永远匹配）
su -c 'python3 tools/make_boost.py --out /sdcard/vib_boost'
```

生成出来的 `odm/firmware/` 覆盖进模块目录，`original_firmware/` 留着回滚。
这样无论你是什么版本都不会踩坑。

脚本里的增益可调：`--ram-gain 1.85 --step-gain 11.0`

## 踩过的坑

1. **KSU overlay 不改 SELinux 标签。**
   文件放 `/data/adb/modules/<id>/odm/firmware/` 下，标签是 `adb_data_file`；
   而 ueventd 加载固件需要 `vendor_file`。少了 `sepolicy.rule` 或开机 `chcon`，
   内核会疯狂刷 `[haptic_hv]rtp_play: buf_len = 0`，**马达一声不响**——
   但 dumpsys 一切正常、md5 也对得上，极具误导性。

2. **RAM 波形不能持续满幅。** 试过把波形改成「满幅平台保持」，LRA 直接打底爆音。

3. **stepable 的振幅改动要小心「形状」。** 放大没问题，改成方波就毁了。

4. **读 `/sys/class/leds/vibrator/` 下的属性有内核 panic 风险。**
   本项目调试早期，一条 `cat` 循环触发
   `Unable to handle kernel paging request at fffffffffffffffc`，
   `panic_on_oops` 直接重启。诊断请用 `dumpsys vibrator_manager`。

## 实测记录

```
QS 音量/亮度滑块  OplusPrebakedSegment{mEffectId=152, mWaveformId=105, mDuration=66}
键盘              OplusPrebakedSegment{mEffectId=158, mWaveformId=111, mDuration=20}
普通触摸          OplusPrebakedSegment{mEffectId=1,   mWaveformId=2,   mDuration=45}
```

键盘只有 20ms，天然「短促无力」，这是它比其他场景弱的结构性原因；
本次模块通过放大共享的 stepable 模板改善了这一点，但没有改动它的时长。

## 致谢

- 波形固件格式解析：[kde-yyds/aw8697-firmware-tools](https://github.com/kde-yyds/aw8697-firmware-tools)
- AW8697 驱动参考：[XagaForge/android_kernel_xiaomi_mt6895](https://github.com/XagaForge/android_kernel_xiaomi_mt6895)

## 许可

MIT。风险自负。
