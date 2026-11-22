# 真我 Neo8 振动增强模块

> **本项目大量内容由 AI 生成。**
>
> 模块代码、波形数据、逆向分析结论与本文档，绝大部分由 AI 助手（DeepSeek / 奶汐）在实机上边跑边写完成；人类负责提出方向、实际体感测试和拍板。
> 波形参数是**反复重启实测**调出来的，不是理论推导。

---

## 怎么用

**只有两条路，二选一：**

### 路线 A：自己生成（推荐，任何版本都能用）

```sh
# 1. 检查你的机器（不改任何东西）
su -c 'python3 tools/make_boost.py --check'

# 2. 如果结论是「可以生成」，执行：
su -c 'python3 tools/make_boost.py --out /sdcard/vib_boost'

# 3. 把生成的文件放进模块目录
su -c 'cp -r /sdcard/vib_boost/odm /data/adb/modules/vib_wave_boost/'
su -c 'chcon -R u:object_r:vendor_file:s0 /data/adb/modules/vib_wave_boost/odm/firmware/'

# 4. 重启
```

需要 python3。手机上没有的话：Termux 里 `pkg install python`，或者把两个固件拷到电脑上跑。

### 路线 B：直接刷预置包（仅限固件完全一致的机器）

```sh
su -c 'md5sum /odm/firmware/aw8697_haptic_170.bin'
```

**必须等于 `8bb3e6427579954b3e0848e8a463ce84`**，否则走路线 A。
（这个 md5 必须在**模块未安装**时查，装过模块后 `/odm/firmware` 会被 overlay 覆盖，读到的是改过的文件。）

确认一致 → 从 [Releases](../../releases) 下载 zip → KSU 管理器安装 → 重启。

### 为什么要两条路

`aw8697_haptic_170.bin` 里带**描述符表（各波形的 RAM 起止地址）**，固件版本一变地址表就变，
直接套用别人的文件会让波形错位，轻则没声音重则异常。
`make_boost.py` 是读**你自己机器上的文件**再放大，所以永远匹配。

---

## 效果

| 通道 | 文件 | 参数 | 体感 |
|---|---|---|---|
| 系统触摸 / 点击 / 长按 | `aw8697_haptic_170.bin`（RAM 波形） | **1.85x** + 软削顶 | 更「实」 |
| QS 音量/亮度滑块、键盘、无级强度 | `aw8697_stepable_regulate_RTP_105_174Hz.bin` | 正弦 **11x** | 更「足」，保持细腻 |
| 通知 / 媒体 | `service.sh` 写 Settings | 通知 1800→2400、媒体 MEDIUM→HIGH | 通知 +33%，媒体 ×1.4 |

强度只在该项为空时写入，**不覆盖你手动调过的值**。

## 卸载

```sh
su -c 'touch /data/adb/modules/vib_wave_boost/remove && reboot'
su -c 'settings delete system notification_stepless_vibration_intensity'
su -c 'settings delete system media_vibration_intensity'
```

## 调参刻度

| 通道 | 偏轻 | 甜点 | 红线 |
|---|---|---|---|
| RAM 波形 | 1.35x | 1.7 ~ 1.85x | **2.0x 以上 LRA 打底，听到「噼」的爆音** |
| stepable | 原厂峰值 12（几乎没感觉） | 8 ~ 11x | 12×11=132 已触 int8 上限，再高只能削顶，会变「嗡嗡」粗糙 |

**stepable 必须保持正弦。** 试过方波化：QS 滑块当场变成转子马达那种嗡嗡声。

```sh
python3 tools/make_boost.py --out ./out --ram-gain 1.7 --step-gain 8
```

## 两条独立通道（实测结论）

| 场景 | 判定证据 | 数据源 |
|---|---|---|
| 系统触摸 | 把 RAM 波形全置零 → 触摸彻底没声 | `aw8697_haptic_170.bin` |
| 键盘 / QS 滑块 | RAM 全置零后键盘照响 | `stepable_...105...bin` |

驱动日志 `[haptic_hv]`：
```
rtp_play: buf_len = 415   ← stepable 去头 8 字节（423-8）
rtp_play: buf_len = 349   ← RAM 波形 [0]
```

原厂 stepable 峰值只有 **12**（不到满幅 10%），这是原厂 QS 滑块几乎没感觉的根本原因。

## 文件格式

```
aw8697_haptic_170.bin
  0x00-0x01  16bit 校验和（大端）= sum(data[2:]) & 0xFFFF
  0x02-0x03  base address（0x0800）
  0x04       version
  0x05-0x30  描述符表，每波形 RAM 起止地址（大端）
  0x31+      波形数据，int8 采样 @24kHz
  文件偏移 = RAM 地址 - 0x07FC

aw8697_stepable_regulate_RTP_105_174Hz.bin
  裸 int8 采样，无头部。39~367 发声，其余静音。峰值 12。
```

## 踩过的坑

1. **KSU overlay 不改 SELinux 标签。**
   模块文件标签是 `adb_data_file`，ueventd 加载固件需要 `vendor_file`。
   少了 `sepolicy.rule` 或开机 `chcon`，内核狂刷 `[haptic_hv]rtp_play: buf_len = 0`，
   **马达一声不响**，但 dumpsys 一切正常、md5 也对得上，极具误导性。

2. **模块生效后 `/odm/firmware` 就被 overlay 覆盖了**，
   此时读该路径得到的 md5 是改过的文件。任何「比对 md5」的判断都必须在安装前做。

3. **RAM 波形不能持续满幅。** 改成「满幅平台保持」会让 LRA 打底爆音。

4. **读 `/sys/class/leds/vibrator/` 下的属性有内核 panic 风险。**
   调试早期一条 `cat` 循环触发 `Unable to handle kernel paging request at fffffffffffffffc`，
   `panic_on_oops` 直接重启。诊断请用 `dumpsys vibrator_manager`。

## 实测记录

```
QS 音量/亮度滑块  OplusPrebakedSegment{mEffectId=152, mWaveformId=105, mDuration=66}
键盘              OplusPrebakedSegment{mEffectId=158, mWaveformId=111, mDuration=20}
普通触摸          OplusPrebakedSegment{mEffectId=1,   mWaveformId=2,   mDuration=45}
```

键盘只有 20ms，天然短促，这是它比别的场景弱的结构性原因。

## 致谢

- 固件格式：[kde-yyds/aw8697-firmware-tools](https://github.com/kde-yyds/aw8697-firmware-tools)
- 驱动参考：[XagaForge/android_kernel_xiaomi_mt6895](https://github.com/XagaForge/android_kernel_xiaomi_mt6895)

## 许可

MIT。使用风险自负。
