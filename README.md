# ⚠️ 警告 – 免责声明

**请仔细阅读此免责声明。**

我们不承担以下任何情况的责任：
- 设备变砖、恢复分区丢失
- 存储卡、电源管理芯片、内存、显示芯片、CPU 损坏
- 小米的任何意外操作
- 宠物或人员伤亡、核战争
- 因忘记切回 Android 导致闹钟未响而被解雇
- 地震海啸等任何自然灾害
- 刷机刷一半没吃饭饿死了
- 刷机刷一半没喝水渴死了
- 刷机刷一半忘记吸氧憋死了
- 因变砖引发任何疾病死了
- 因给我提Issues没有人回复气死了
- 等各种各样的原因

本仓库中的所有文件均由社区用户贡献。提供的指南及文件均为“按现状”提供，**请自行承担使用风险**，并严格遵循每一步骤。

我不会对您的设备因任何原因变砖负责，除非您愿意打钱：）

**如果您不熟悉平板改装、分区表操作或对设备变砖感到极度不安，请立即关闭此页面！您已经收到警告，任何后果自负！再次强调，您已收到警告！**

---

## 📊 功能状态（摘要）

|类别| 功能|状态| 备注|
|--------|------------|----------|--------------------------|
|核心|系统刷写|正常|仅限Debian|
|核心|屏幕/触摸|正常|含休眠/亮度/触摸|
|核心|键盘/触摸板|部分正常|官方键盘有概率无响应，需要重新与触点连接|
|连接|Wi-Fi|正常|部分地区需要设置wifi区域码才能正常使用5GHz Wifi|
|连接|蓝牙|正常||
|连接|Type-C|部分正常|Type-C与键盘触点冲突，官方键盘需要重新与触点连接才能正常检测|
|多媒体|音频/相机|正常|相机效果劣于Android|
|传感器|全部|正常|自动旋转/亮度/霍尔等|
|手写笔|测试|故障|只有笔充电可用，充电修复来自[xiaomi-pen-status](https://github.com/ianchb/xiaomi-pen-status)|

> 完整功能状态表请查阅 [PostmarketOS wiki](https://wiki.postmarketos.org/wiki/Xiaomi_Pad_6S_Pro_12.4_(xiaomi-sheng))

---

## 🔐 登录凭证

默认系统账户：

- **用户名**: `luser`
- **密码**: `luser`

---

## 📖 详细指南（Wiki）

所有安装、配置、切换系统的详细步骤均已移至 **Wiki**，请根据需求点击以下链接：

| 指南                                 | 说明                                     |
| ------------------------------------ | ---------------------------------------- |
| [📥 安装指南](https://github.com/code002-2/Xiaomi-pad-6s-pro-Linux/wiki/安装指南) | 分区、刷写 rootfs 与 boot 镜像，首次扩容 |
| [🔄 切换操作系统](https://github.com/code002-2/Xiaomi-pad-6s-pro-Linux/wiki/切换操作系统) | Android ↔ Linux 的无缝切换方法           |
| [⌨️ 官方键盘支持](https://github.com/code002-2/Xiaomi-pad-6s-pro-Linux/wiki/官方键盘支持) | Pogo Pin 键盘认证服务配置                |
| [📡 传感器支持](https://github.com/code002-2/Xiaomi-pad-6s-pro-Linux/wiki/传感器支持) | 加速度计、光线传感器等服务启用           |
| [🧩 推荐的 GNOME 扩展](https://github.com/code002-2/Xiaomi-pad-6s-pro-Linux/wiki/推荐的GNOME扩展) | 提升平板触摸体验的扩展列表               |
| [steam安装教程](https://github.com/code002-2/Xiaomi-pad-6s-pro-Linux/wiki/steam) | 适用于linux arm64的steam安装教程

---

## 🎥 软件测试视频

[小米pad6spro Debian启动！-哔哩哔哩](https://www.bilibili.com/video/BV1za5g6wEx8)

[小米pad6spro debian hangover wine+dxvk测试-哔哩哔哩](https://www.bilibili.com/video/BV1Be5y6ZEiK)

[小米pad6spro debian蓝牙手柄+vulkan小游戏测试-哔哩哔哩](https://www.bilibili.com/video/BV1rg516PEWt)

## 📝 快速预览（核心步骤）

如果你想快速了解安装流程，概览如下（详细操作请务必阅读 Wiki）：

1. 解锁 bootloader，确保仅有 Android 系统
2. 下载 `rootfs` 和 `boot` 镜像，以及 `parted` 工具
3. 通过 TWRP 和 `parted` 重分区（删除 userdata，新建 userdata + linux）
4. 刷写镜像到槽位 B：`fastboot flash boot_b` 和 `fastboot flash linux`
5. 激活槽位 B 并重启
6. 首次启动后执行 `sudo resize2fs /dev/sda30` 扩容

---

## ❤️ 致谢

感谢所有社区贡献者的测试与文件提供。
[@map220v](https://github.com/map220v) 主线内核开发，设备驱动等，
[@ianchb](https://github.com/ianchb) MIPPS快充补丁，触控笔充电，
[@alghiffaryfa19](https://github.com/alghiffaryfa19) 该设备项目的上游，
[@code002-2](https://github.com/code002-2) 二次开发改进

以及相关的贡献者

# 相关群组

[![Channel](https://img.shields.io/badge/Follow-Telegram-blue.svg?logo=telegram)](https://t.me/Pad_6S_Pro_Linux_Chat) [![QQ Group](https://img.shields.io/badge/Follow-QQ-12B7F5.svg?logo=qq&logoColor=white)](https://qun.qq.com/universal-share/share?ac=1&authKey=du2KyTQBUaKnU5ENPe5BD7r35s8t6m5qXuVHU656cEDmrpMVq0rTlUH1PuSLVN6n&busi_data=eyJncm91cENvZGUiOiIxMDkyMjc0NjU3IiwidG9rZW4iOiJQdDJqVnBGa1UzcFgyN0ZXSkxHYUhLbDhzZkN4N2g5d0ZoZFdFQkJyZVVMTzVkeitCTXArc2xKU1ZGRVpBd3VmIiwidWluIjoiMzQ5NzEzMDI2MSJ9&data=3eANpQ8g5VfxnuvZSz0QtAoD0D5o6yD7M9Gm8JQHbFs83icXp3G6bZYVVUHW47HKgL_Rq5ecivzzo8PNL8FCAQ&svctype=4&tempid=h5_group_info)

**谨慎操作 – 祝使用愉快！**
