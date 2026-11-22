# Realme Neo8 振动增强模块

针对 realme Neo8 (RMX8899) 的 AW8697 触觉芯片，修改其固件波形数据以提升振动强度。

> 本项目由 AI 辅助完成：波形参数由 AI 助手在实机上反复测试得出，逆向分析与代码编写亦由 AI 完成。
> 项目维护者负责提出方向、实际体感评估与发布决策。

## 1. 适用环境

| 项目 | 说明 |
|---|---|
| 机型 | realme Neo8 / RMX8899 |
| 系统 | realmeUI 7.0 / Android 17 |
| 芯片 | AW8697（AAC RichTap），驱动日志前缀 `[haptic_hv]` |
| 环境 | KernelSU / ReSukiSU（依赖 overlay 与 sepolicy 注入） |

固件版本差异的处理见第 6 节。

## 2. 实现原理

### 2.1 两条独立的振动通道

实测确认系统振动由两条互不相干的通道驱动：

| 通道 | 数据来源 | 覆盖场景 | 判定依据 |
|---|---|---|---|
| RAM 波形表 | `/odm/firmware/aw8697_haptic_170.bin` | 系统触摸、点击、长按 | 将该文件所有波形置零后，触摸类振动完全消失 |
| RTP 流 | `/odm/firmware/aw8697_stepable_regulate_RTP_105_174Hz.bin` | QS 滑块、键盘、无级强度 | RAM 波形全置零后，键盘振动不受影响 |

驱动日志可区分两者：

```
[haptic_hv]rtp_play: buf_len = 415    // stepable 数据（423 - 8 字节头部）
[haptic_hv]rtp_play: buf_len = 349    // RAM 波形 [0]
```

系统各场景实际参数：

```
QS 音量/亮度滑块   OplusPrebakedSegment{mEffectId=152, mWaveformId=105, mDuration=66}
键盘               OplusPrebakedSegment{mEffectId=158, mWaveformId=111, mDuration=20}
普通触摸           OplusPrebakedSegment{mEffectId=1,   mWaveformId=2,   mDuration=45}
```

原厂 `stepable_regulate` 峰值仅 12（满幅 127 的 9.4%），这是 QS 滑块振动极弱的直接原因。

### 2.2 固件文件格式

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

`aw8697_stepable_regulate_RTP_105_174Hz.bin`：裸 int8 采样，无头部、无地址表，因此尺寸可任意变化，只影响振动时长。

原厂版本 423 字节、峰值 12、174Hz 正弦，前后带静音填充。模块内预置的是重新设计的版本（1084 字节 / 45.2ms），并非原厂的等比放大：

| 参数 | 原厂 | 模块内 |
|---|---|---|
| 长度 | 423 采样（17.6ms） | 1084 采样（45.2ms） |
| 峰值 | 12 | 127 |
| RMS | 5.9 | 96.6 |
| 波形 | 174Hz 正弦，缓慢起伏 | 高占空比软方波（边沿 5 采样、平台约 74%），尾部带反向刹车 |

长度对齐到 45ms，与系统点击请求的 duration（45ms）匹配，避免振动提前结束后出现「空心感」；尾部反向刹车用于抑制 LRA 收尾时的弹簧拖尾。

## 3. 模块参数

| 修改对象 | 处理方式 | 说明 |
|---|---|---|
| RAM 波形 [0][1][2][3][5] | 增益 1.85x，超出 ±127 部分削顶 | 峰值原本已接近满幅，实际 RMS 提升 35%~49% |
| stepable 模板 | 重新设计波形（1084 采样，见 2.2） | RMS 5.9 → 96.6 |
| 通知振动强度 | 1800 → 2400 | Settings.System，+33% |
| 媒体振动强度 | MEDIUM → HIGH | Settings.System，系数 1.4 |

强度项仅在对应 Settings 值为空时写入，不覆盖用户手动调整的值。

### 参数调整范围

RAM 波形增益：

- 1.35x：偏弱
- 1.70 ~ 1.85x：推荐
- 2.00x 以上：LRA 达到机械限位，产生可闻的撞击噪声

stepable：模块内为定制波形，不建议用生成器覆盖。若确需调整：

```sh
BUILD_STEP=1 STEP_GAIN=11 sh gen.sh
```

注意该模式为纯等比放大，会丢失定制波形的时长与刹车设计。实测把原厂正弦改为硬方波后，QS 滑块振动会呈现电机嗡鸣感——软方波（边沿带过渡）则无此问题。

## 4. 安装

```
KernelSU / ReSukiSU 管理器 → 模块 → 从本地安装 → 选择 zip → 重启
```

必须重启。波形数据在驱动 probe 阶段一次性写入芯片 RAM，系统未提供热重载接口。

## 5. 验证

安装后运行：

```sh
su -c 'sh /data/adb/modules/vib_wave_boost/verify.sh'
```

判据为驱动加载固件时自行计算的校验和：

```
[haptic_hv]ram_load: check sum pass : 0x0F76
```

该值等于模块内文件的校验和，即证明驱动加载的是替换后的文件。

**注意**：请于重启后 5 分钟内执行。内核环形日志容量有限，开机较久后加载记录会被覆盖，此时脚本会输出「无法确认」，而非误报成功。

输出项：

| 检查项 | 通过条件 |
|---|---|
| 模块状态 | 目录存在，未标记 disable / remove |
| overlay | `KSU on /odm/firmware` 已挂载 |
| RAM 固件 | 校验和与驱动日志一致 |
| stepable | 文件尺寸与驱动日志 `rtp file: ... size = N bytes` 一致 |
| 故障 | 无 `buf_len = 0` 记录 |

## 6. 固件版本差异

`aw8697_haptic_170.bin` 含描述符表，固件版本变化时地址表也随之变化，直接套用其他机器的文件可能导致波形错位。
若目标机器该文件与模块内不一致，请使用附带工具按本机文件重新生成：

```sh
su -c 'python3 tools/make_boost.py --check'                     # 检查结构
su -c 'python3 tools/make_boost.py --out /sdcard/vib_boost'     # 生成
su -c 'python3 tools/make_boost.py --out ./out --ram-gain 1.7'  # 自定义增益
```

工具解析校验和、描述符表与波形边界，不依赖 md5 比对。生成的 `odm/firmware/` 覆盖至模块目录后需执行 `chcon u:object_r:vendor_file:s0` 并重启。

`aw8697_stepable_regulate_RTP_105_174Hz.bin` 无表结构，模块内预置的定制波形可直接使用，无需按版本重新生成。

## 7. 故障排查

| 现象 | 原因 | 处理 |
|---|---|---|
| 马达完全无振动 | 模块 overlay 后 SELinux 标签为 `adb_data_file`，ueventd 需要 `vendor_file` | 确认 `sepolicy.rule` 与 `post-fs-data.sh` 均存在且生效 |
| 内核刷屏 `buf_len = 0` | 同上，驱动读不到波形数据 | 同上 |
| 校验和不一致 | 驱动加载的仍是原厂文件 | 检查 overlay 是否挂载成功 |
| 振动变粗糙、有撞击声 | RAM 波形增益过高 | 降至 1.7x 重新生成 |
| QS 滑块振动发闷、嗡鸣 | stepable 被改为非正弦波形 | 恢复正弦，仅调整增益 |

`/sys/class/leds/vibrator/` 目录下的属性节点存在内核崩溃风险：调试期间对多个节点批量执行 `cat` 触发过
`Unable to handle kernel paging request at fffffffffffffffc`，`panic_on_oops` 导致重启。
诊断建议使用 `dumpsys vibrator_manager`。

## 8. 卸载

```sh
su -c 'touch /data/adb/modules/vib_wave_boost/remove && reboot'
su -c 'settings delete system notification_stepless_vibration_intensity'
su -c 'settings delete system media_vibration_intensity'
```

删除模块并重启后，overlay 失效，系统自动回落到原厂固件。

## 9. 参考

- 固件格式解析：[kde-yyds/aw8697-firmware-tools](https://github.com/kde-yyds/aw8697-firmware-tools)
- 驱动实现：[XagaForge/android_kernel_xiaomi_mt6895](https://github.com/XagaForge/android_kernel_xiaomi_mt6895)

## 10. 许可

MIT License。使用风险自负。
