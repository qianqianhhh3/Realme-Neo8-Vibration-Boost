# Realme Neo8 振动增强模块

针对真我 Neo8（RMX8899）的 KernelSU 模块，用于调整 AW8697 振动芯片的波形通道与系统振动强度，改善触摸、键盘和 QS 滑块的手感。

适用于 realme UI 7.0 / Android 17，其他系统版本未做验证。

## 改动内容

| 场景 | 改动 |
| --- | --- |
| 系统触摸、点击、长按 | RAM 波形 `aw8697_haptic_170.bin` 整体放大 1.85 倍，超出部分软削顶 |
| 键盘、QS 音量/亮度滑块、无级强度 | stepable 波形 `aw8697_stepable_regulate_RTP_105_174Hz.bin` 重制：3 个满幅正弦周期，末尾 20 采样线性淡出，331 字节，约 16 ms |
| 通知强度 | 1800 → 2400 |
| 媒体强度 | MEDIUM → HIGH |

强度两项仅在系统设置为空时写入，不会覆盖手动调整过的值。

## 兼容性

安装前核对原厂固件：

```sh
su -c 'md5sum /odm/firmware/aw8697_haptic_170.bin'
```

输出应为 `8bb3e6427579954b3e0848e8a463ce84`。

不匹配表示固件版本不同，模块内的波形数据与该机器不兼容，刷入后振动可能完全失效。固件被修改过的机器需先恢复原厂文件。

运行环境需要 KernelSU 或 ReSukiSU。模块通过 overlay 替换 `/odm/firmware` 下的文件，并由 `sepolicy.rule` 赋予正确的 SELinux 上下文。

## 安装

在 KernelSU / ReSukiSU 管理器的模块页面选择「从本地安装」，选中 zip 后重启设备。

波形在驱动 probe 阶段一次性写入芯片 RAM，没有运行时重载的接口，因此必须重启才会生效。

## 生效确认

```sh
su -c 'ls -l /odm/firmware/aw8697_stepable_regulate_RTP_105_174Hz.bin'
```

文件大小为 331 字节即表示模块已加载。

## 卸载

```sh
su -c 'touch /data/adb/modules/vib_wave_boost/remove && reboot'
```

重启后 overlay 移除，波形恢复原厂。

模块写入的两项系统设置不会自动清除，如需恢复默认值：

```sh
su -c 'settings delete system notification_stepless_vibration_intensity'
su -c 'settings delete system media_vibration_intensity'
```

`original_firmware/` 目录内是两个原厂固件，可用于手动恢复，也可作为自行修改的基准。

## 参数说明

RAM 波形的放大倍数：1.35 倍改动较轻微，1.7 至 1.85 倍之间差异明显。超过 2 倍时 LRA 处于满幅状态，会出现明显破音。

stepable 波形需要保持单频正弦。加入递减脉冲、反向制动或改用方波都会引入谐波，使滑块和键盘的声音变粗糙。周期数 3 个为宜，继续增加会让反馈变拖沓。

## 固件格式

`aw8697_haptic_170.bin`，4611 字节：

```
偏移      内容
0x00-01   16 位校验和，大端，= sum(data[2:]) & 0xFFFF
0x02-03   基地址，0x0800
0x04      版本
0x05-30   波形描述符表，每项为该波形的 RAM 起止地址
0x31-     波形数据，int8 采样，24 kHz
文件偏移 = RAM 地址 - 0x07FC
```

共 11 个波形：[0] 349 字节，[1][3][5] 各 415 字节，[2] 960 字节，[9] 344 字节。

`aw8697_stepable_regulate_RTP_105_174Hz.bin` 为无头部的裸采样数据，播放时从第 8 字节开始读取。

修改任一文件后必须重新计算校验和，否则驱动拒绝加载，日志输出 `check sum fail`。

## 已知问题

- 模块目录被 overlay 覆盖时，修改 `/data/adb/modules/<id>/odm/firmware` 下的文件不会同步到 `/odm`。调试时需先 `umount` 该目录，再 `mount --bind` 指向修改后的目录，并重启振动 HAL。
- 不建议读取 `/sys/class/leds/vibrator/` 下的属性节点。部分节点读取不返回 EOF，调试过程中曾触发内核空指针异常，因 `panic_on_oops` 直接重启。诊断请用 `dumpsys vibrator_manager`。
- 安装模块后若振动完全失效，先确认 `/odm/firmware` 下文件的 SELinux 上下文为 `vendor_file`，再看内核日志是否持续输出 `[haptic_hv]rtp_play: buf_len = 0`。

## 版本历史

| 版本 | 内容 |
| --- | --- |
| v1.0 | RAM 波形放大 1.85 倍并软削顶；stepable 波形正弦放大；通知与媒体强度调整 |
| v1.1 | stepable 波形重制为 3 个满幅正弦周期加线性淡出，去除原厂尾部递减脉冲 |

## 致谢

- 波形固件格式解析：[kde-yyds/aw8697-firmware-tools](https://github.com/kde-yyds/aw8697-firmware-tools)
- AW8697 驱动参考：[XagaForge/android_kernel_xiaomi_mt6895](https://github.com/XagaForge/android_kernel_xiaomi_mt6895)

## 许可

MIT
