# Realme Neo8 振动增强模块

针对 realme Neo8 (RMX8899) 的 AW8697 触觉芯片，修改固件波形数据以提升振动强度。

> 本项目由 AI 辅助完成：波形参数由 AI 助手在实机上反复测试得出，逆向分析与代码编写亦由 AI 完成。
> 项目维护者负责提出方向、实际体感评估与发布决策。

## 1. 适用环境

| 项目 | 说明 |
|---|---|
| 机型 | realme Neo8 / RMX8899 |
| 系统 | realmeUI 7.0 / Android 17 |
| 芯片 | AW8697（AAC RichTap），驱动日志前缀 `[haptic_hv]` |
| 环境 | KernelSU / ReSukiSU（依赖 overlay 与 sepolicy 注入） |

## 2. 模块内容

| 修改对象 | 处理方式 | 效果 |
|---|---|---|
| RAM 波形 [0][1][2][3][5] | 增益 1.85x，超出 ±127 削顶 | 系统触摸 / 点击 / 长按 RMS 提升 35%~49% |
| stepable 模板 | 重新设计波形，1084 采样（45.2ms） | QS 滑块 / 键盘 RMS 5.9 → 96.6 |
| 通知振动强度 | Settings 1800 → 2400 | +33% |
| 媒体振动强度 | Settings MEDIUM → HIGH | 系数 1.4 |

强度项仅在对应 Settings 值为空时写入，不覆盖用户手动调整。

## 3. 实现原理

### 3.1 两条独立的振动通道

| 通道 | 数据来源 | 覆盖场景 | 判定依据 |
|---|---|---|---|
| RAM 波形表 | `aw8697_haptic_170.bin` | 系统触摸、点击、长按 | 将该文件所有波形置零后，触摸类振动完全消失 |
| RTP 流 | `aw8697_stepable_regulate_RTP_105_174Hz.bin` | QS 滑块、键盘、无级强度 | RAM 波形全置零后，键盘振动不受影响 |

驱动日志可区分两者：

```
[haptic_hv]rtp_play: buf_len = 415    // 原厂 stepable（423 - 8 字节头部）
[haptic_hv]rtp_play: buf_len = 349    // RAM 波形 [0]
```

系统各场景实际参数：

```
QS 音量/亮度滑块   OplusPrebakedSegment{mEffectId=152, mWaveformId=105, mDuration=66}
键盘               OplusPrebakedSegment{mEffectId=158, mWaveformId=111, mDuration=20}
普通触摸           OplusPrebakedSegment{mEffectId=1,   mWaveformId=2,   mDuration=45}
```

原厂 stepable 峰值仅 12（满幅 127 的 9.4%），这是 QS 滑块振动极弱的直接原因。

### 3.2 固件格式

`aw8697_haptic_170.bin`（4611 字节）：

```
偏移        内容
0x00-0x01   16 位校验和，大端，等于 sum(data[2:]) & 0xFFFF
0x02-0x03   RAM 基地址（0x0800）
0x04        版本号
0x05-0x30   描述符表，每个波形的 RAM 起止地址（大端）
0x31-       波形数据，int8 有符号采样，采样率 24kHz

文件偏移 = RAM 地址 - 0x07FC
```

共 11 个波形，尺寸依次为 349 / 415 / 960 / 415 / 1 / 415 / 233 / 394 / 139 / 344 / 496 字节。
修改后必须重算校验和，否则驱动拒绝加载（`check sum fail`）。

`aw8697_stepable_regulate_RTP_105_174Hz.bin`：裸 int8 采样，无头部、无地址表，尺寸可变，只影响时长。

| 参数 | 原厂 | 模块内 |
|---|---|---|
| 长度 | 423 采样（17.6ms） | 1084 采样（45.2ms） |
| 峰值 | 12 | 127 |
| RMS | 5.9 | 96.6 |
| 波形 | 174Hz 正弦 | 高占空比软方波（边沿 5 采样、平台约 74%），尾部反向刹车 |

长度对齐 45ms，与系统点击请求的 duration 一致，避免振动提前结束后出现「空心感」；尾部刹车用于抑制 LRA 收尾的弹簧拖尾。

## 4. 安装

```
KernelSU / ReSukiSU 管理器 → 模块 → 从本地安装 → 选择 zip → 重启
```

必须重启。波形数据在驱动 probe 阶段一次性写入芯片 RAM，系统未提供热重载接口。

## 5. 验证

模块卡片第二个按钮打开 WebUI，点「检查是否生效」；或直接运行：

```sh
su -c 'sh /data/adb/modules/vib_wave_boost/verify.sh'
```

判据为驱动加载固件时自行计算的校验和：

```
[haptic_hv]ram_load: check sum pass : 0x0F76
```

该值等于模块内文件的校验和，即证明驱动加载的是替换后的文件。

**注意**：请于重启后 5 分钟内执行。内核环形日志容量有限，开机较久后加载记录会被覆盖，此时脚本会输出「无法确认」，而非误报成功。

## 6. 故障排查

| 现象 | 原因 | 处理 |
|---|---|---|
| 马达完全无振动 | overlay 后 SELinux 标签为 `adb_data_file`，ueventd 需要 `vendor_file` | 确认 `sepolicy.rule` 与 `post-fs-data.sh` 存在且生效 |
| 内核刷屏 `buf_len = 0` | 同上，驱动读不到波形数据 | 同上 |
| 校验和不一致 | 驱动加载的仍是原厂文件 | 检查 overlay 是否挂载成功 |
| 振动变粗糙、有撞击声 | RAM 波形增益过高 | 需降低增益重新制作固件 |

调试期间对 `/sys/class/leds/vibrator/` 下多个属性节点批量执行 `cat`，曾触发
`Unable to handle kernel paging request at fffffffffffffffc`，`panic_on_oops` 导致重启。
诊断建议使用 `dumpsys vibrator_manager`。

## 7. 卸载

```sh
su -c 'touch /data/adb/modules/vib_wave_boost/remove && reboot'
su -c 'settings delete system notification_stepless_vibration_intensity'
su -c 'settings delete system media_vibration_intensity'
```

删除模块并重启后，overlay 失效，系统自动回落到原厂固件。

## 8. 参考

- 固件格式解析：[kde-yyds/aw8697-firmware-tools](https://github.com/kde-yyds/aw8697-firmware-tools)
- 驱动实现：[XagaForge/android_kernel_xiaomi_mt6895](https://github.com/XagaForge/android_kernel_xiaomi_mt6895)

## 9. 许可

MIT License。使用风险自负。
