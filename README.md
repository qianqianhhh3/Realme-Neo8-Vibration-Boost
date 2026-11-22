# 真我 Neo8 振动增强模块

> **本项目大量内容由 AI 生成。**
>
> 模块代码、波形数据、逆向分析结论与本文档，绝大部分由 AI 助手（DeepSeek / 奶汐）在实机上边跑边写完成；
> 人类负责提出方向、实际体感测试和拍板。波形参数是**反复重启实测**调出来的，不是理论推导。

---

## 快速开始

```sh
# 1. 下载 Releases 里的 zip，KSU 管理器安装
# 2. 重启
# 3. 重启后 5 分钟内，跑这个确认到底成没成：
su -c 'sh verify.sh'
```

看到 **「结论：完全生效 ✅」** 就完事了。

没生效的话，看下面「出问题怎么办」。

---

## 验证：怎么知道成没成

`tools/verify.sh` 会输出这样一份报告：

```
[1] 模块安装状态          [✓] 模块目录存在且已启用（真我neo8震动增强模块）
[2] overlay 挂载          [✓] KSU overlay 已挂载到 /odm/firmware
[3] RAM 波形固件          [✓] 模块文件 4611 字节，校验和 0x0F76
                          [✓] overlay 后 /odm/firmware 内容 = 模块文件（替换成功）
                          [✓] ★ 校验和一致 —— 驱动加载的就是模块固件，已生效
[4] stepable 模板         [✓] 模块文件 423 字节，峰值 127（原厂是 12）
                          [✓] ★ 尺寸一致 —— 驱动读的就是模块这份
[5] 故障检查              [✓] 没有 buf_len = 0 刷屏
```

**判断依据不是 md5，是驱动自己算的校验和。**
驱动加载 RAM 固件时会打印 `[haptic_hv]ram_load: check sum pass : 0x0F76`，
这个值等于模块里那文件的校验和，就证明驱动读的确实是替换后的固件——这是唯一无法伪造的证据。

> ⚠️ 一定要**重启后立刻**跑。内核环形日志会被冲掉（开机久了就查不到加载记录了），
> 那时脚本会诚实地说「无法确认」，而不是假装成功。

---

## 出问题怎么办

| verify.sh 报告 | 意思 | 怎么办 |
|---|---|---|
| `[✗] 没有 overlay` | 模块没挂上 | 确认是 KSU/ReSukiSU，不是普通 Magisk |
| `[✗] 校验和不一致` | 驱动加载的不是模块文件 | 多半是 SELinux 拦了，检查 `sepolicy.rule` |
| `[✗] buf_len = 0 刷屏` | 典型 SELinux 拦截症状，马达会完全没反应 | 同上，或先 `rm` 模块重启恢复 |
| `[?] 无法确认` | 日志被冲掉了 | 重启后立刻再跑 |
| 全部 ✓ 但手感没变 | 确实生效了，只是这版参数不合口味 | 用下面的生成器调参数 |

**调参数 / 固件版本不同** → 用生成器按你自己机器的文件重新生成：

```sh
su -c 'python3 tools/make_boost.py --check'                        # 先看结构
su -c 'python3 tools/make_boost.py --out /sdcard/vib_boost'        # 再生成
su -c 'python3 tools/make_boost.py --out ./out --ram-gain 1.7'     # 调增益
```

把生成的 `odm/firmware/` 覆盖进 `/data/adb/modules/vib_wave_boost/`，`chcon` 一下，重启。

---

## 效果与参数

| 通道 | 文件 | 参数 | 体感 |
|---|---|---|---|
| 系统触摸 / 点击 / 长按 | `aw8697_haptic_170.bin`（RAM 波形） | **1.85x** + 软削顶 | 更「实」 |
| QS 音量/亮度滑块、键盘、无级强度 | `aw8697_stepable_regulate_RTP_105_174Hz.bin` | 正弦 **11x** | 更「足」，保持细腻 |
| 通知 / 媒体强度 | `service.sh` 写 Settings | 通知 1800→2400、媒体 MEDIUM→HIGH | +33% / ×1.4 |

强度只在该项为空时写入，**不覆盖你手动调过的值**。

### 调参刻度

| 通道 | 偏轻 | 甜点 | 红线 |
|---|---|---|---|
| RAM 波形 | 1.35x | 1.7 ~ 1.85x | **2.0x 以上 LRA 打底，听到「噼」的爆音** |
| stepable | 原厂峰值 12（几乎没感觉） | 8 ~ 11x | 12×11=132 已触 int8 上限，再高只能削顶，会变「嗡嗡」粗糙 |

**stepable 必须保持正弦。** 试过方波化：QS 滑块当场变成转子马达那种嗡嗡声。

## 卸载

```sh
su -c 'touch /data/adb/modules/vib_wave_boost/remove && reboot'
su -c 'settings delete system notification_stepless_vibration_intensity'
su -c 'settings delete system media_vibration_intensity'
```

---

## 原理

### 两条独立通道

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

### 文件格式

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

stepable 是纯采样无表结构，**多大尺寸都能安全替换**，大小只影响时长。
RAM 固件带描述符表，版本差异大时用生成器，别硬套别人的文件。

## 踩过的坑

1. **KSU overlay 不改 SELinux 标签。** 模块文件标签是 `adb_data_file`，
   ueventd 加载固件需要 `vendor_file`。少了 `sepolicy.rule` 或开机 `chcon`，
   内核狂刷 `[haptic_hv]rtp_play: buf_len = 0`，**马达一声不响**，但 dumpsys 一切正常、md5 也对得上。

2. **模块生效后 `/odm/firmware` 就被 overlay 覆盖了**，此时读到的 md5 是改过的文件。
   任何「比对 md5 判断兼容性」的做法都必须在安装前做。

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
