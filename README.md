# 真我 Neo8 震动增强模块

> **本项目大量内容由 AI 生成。**
>
> 模块的代码、波形数据、逆向分析结论与本文档，绝大部分由 AI 助手（DeepSeek / 奶汐）在实机上边跑边写完成，人类主要承担提出方向、实际体感测试与决策。
> 波形参数是在这台机器上**反复试听实测**调出来的，不是理论推导。换机型请先读完「适用条件」。
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
| QS 音量/亮度滑块、键盘、无级强度 | `aw8697_stepable_regulate_RTP_105_174Hz.bin` | 高占空比软方波 + 尾部刹车，**1084 采样** | 更「足」，收尾干净，系统点击不再空心 |
| 通知 / 媒体强度 | `service.sh` 写入 Settings | 通知 1800→2400、媒体 MEDIUM→HIGH | 通知 +33%，媒体 ×1.4 |

强度那两条**只在该项为空时写入**，你手动调过的值不会被覆盖。

## v1.1 改了什么

上一版只做了「放大」，声音变大但问题还在：**收尾发弹、系统点击发空**。

这一版把无级波形整个重做了：

1. **主体改成高占空比软方波**——边沿只留 5 个采样，平台压到半周期的 74%。峰值不变（±127），但同样电压下推到 LRA 上的能量大约 +30%。
2. **尾部加一拍反向刹车**——原厂最后一个半周期从 66 掉到 0 只用 18 个采样，而正常半周期要 45~50 个。等于振子还在冲，驱动被掐断，剩下的动量自己摆完，就是那个「弹簧感」。现在补成 55 → 0 → −44 → 0，把振子按回中位再断。
3. **长度从 423 采样拉到 1084 采样**——`dumpsys` 里系统点击请求的是 `duration=45`，而原厂文件只有约 17ms，后面的时间是空的，所以「响一下就没了」。现在波形能把 45ms 填满。

## 安装

```text
ReSukiSU / KernelSU 管理器 → 模块 → 从本地安装 → 选择 zip → 重启
```

**必须重启**：波形是驱动 probe 时一次性烧进芯片 RAM 的，系统里没有热重载接口。

（调试时可以 `killall vendor.oplus.hardware.vibrator-service` 让 HAL 重读固件，但开机流程还是会用 overlay 里的文件。）

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
| stepable 主体 | 占空比 50% | 边沿 5 采样 / 平台 74% | 硬方波（边沿 0~2 采样）→ 变「嗡嗡」的转子味 |
| stepable 刹车 | −22 | **−44** | −66 以上会变成「咚咚」两下 |

> **方波要「软」。** v1.0 试过粗暴方波化，QS 滑块当场变成转子马达那种嗡嗡声被打回；v1.1 用的是边沿 5 采样的软方波，既能提能量又不刺耳。
> 想自己生成：改 `src/generate_stepable.py` 里的 `HALF / AMPS / EDGE / BRAKE_AMP`，重新生成覆盖即可。

## 原理

### 两条通道，一份模板

| 场景 | 证据 | 数据源 |
|---|---|---|
| 系统触摸 | 把 RAM 波形全置零 → 触摸彻底没声 | `aw8697_haptic_170.bin` 的 RAM 波形表 |
| 键盘 / QS 滑块 / 系统点击 | RAM 全置零后照响不误 | `aw8697_stepable_regulate_RTP_105_174Hz.bin`（RTP 流） |

驱动日志能直接看出走哪条：

```
[haptic_hv]rtp_play: buf_len = 415   ← stepable 去头 8 字节（423-8，v1.1 后为 1076）
[haptic_hv]rtp_play: buf_len = 349   ← RAM 波形 [0]
```

`dumpsys vibrator_manager` 里的请求：

```
QS 音量/亮度滑块  OplusPrebakedSegment{mEffectId=152, mWaveformId=105, mDuration=66}
键盘              OplusPrebakedSegment{mEffectId=159, mWaveformId=112, mDuration=20}
普通触摸          OplusPrebakedSegment{mEffectId=1,   mWaveformId=2,   mDuration=45}
```

注意键盘要 20ms、系统点击要 45ms，**但两者吃的是同一个文件**。原厂文件只有约 17ms，所以键盘刚好够、系统点击却空着——这就是「空心感」的结构性原因。

### 为什么不能靠调数值变强

1. 框架侧 `touch_stepless_vibration_intensity` 封顶 **2400**，再往上调不生效；
2. HAL 会按**峰值**归一化波形，把采样乘 2、乘 3 都会被拉回原强度。

所以只能改**形状**：同样峰值下，方波基波是峰值的 4/π ≈ 1.27 倍，梯形/正弦要低得多。

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

aw8697_stepable_regulate_RTP_105_174Hz.bin
  v1.1：1084B 裸 int8 采样，无头；播放时取 [8:]。
  39 起为波形主体（8 个半周期软方波），末尾 165 采样为反向刹车。
```

改完**必须重算校验和**，否则驱动直接 `check sum fail` 拒绝加载。

## 踩过的坑

1. **KSU overlay 不改 SELinux 标签。**
   文件放 `/data/adb/modules/<id>/odm/firmware/` 下，标签是 `adb_data_file`；
   而 ueventd 加载固件需要 `vendor_file`。少了 `sepolicy.rule` 或开机 `chcon`，
   内核会疯狂刷 `[haptic_hv]rtp_play: buf_len = 0`，**马达一声不响**——
   但 dumpsys 一切正常、md5 也对得上，极具误导性。

2. **overlay 的 lowerdir 是开机快照。**
   热改 `/data/adb/modules/<id>/odm/firmware` 不会反映到 `/odm`。想立刻试听：
   `umount /odm/firmware` → `mount --bind <镜像目录> /odm/firmware` → `killall vendor.oplus.hardware.vibrator-service`。

3. **RAM 波形不能持续满幅。** 试过把波形改成「满幅平台保持」，LRA 直接打底爆音。

4. **stepable 改形状要留边沿。** 硬方波（0~2 采样边沿）会变成嗡嗡声；5 采样边沿是实测能接受的下限。

5. **读 `/sys/class/leds/vibrator/` 下的属性有内核 panic 风险。**
   本项目调试早期，一条 `cat` 循环触发
   `Unable to handle kernel paging request at fffffffffffffffc`，
   `panic_on_oops` 直接重启。诊断请用 `dumpsys vibrator_manager`。

## 版本历史

| 版本 | 内容 |
|---|---|
| v1.0 | RAM 波形 1.85x 软削顶；stepable 正弦 11x 放大；通知/媒体强度 |
| v1.1 | stepable 重做：软方波 + 尾部反向刹车 + 长度 423→1084 采样；修掉收尾弹簧感与系统点击空心 |

## 致谢

- 波形固件格式解析：[kde-yyds/aw8697-firmware-tools](https://github.com/kde-yyds/aw8697-firmware-tools)
- AW8697 驱动参考：[XagaForge/android_kernel_x86_mt6895](https://github.com/XagaForge/android_kernel_xiaomi_mt6895)

## 许可

MIT。风险自负。
