如果你对此项目感兴趣 可以加入我的群聊1092274657

# ⚠️ 警告 – 免责声明

**请仔细阅读此免责声明。**

我们不承担以下任何情况的责任：
- 设备变砖、恢复分区丢失
- 存储卡、电源管理芯片、内存、显示驱动芯片、CPU 损坏
- 小米的任何意外操作
- 宠物或人员伤亡、核战争
- 因忘记切回 Android 导致闹钟未响而被解雇

本仓库中的所有文件均由社区用户贡献。提供的指南及文件均为“按现状”提供，**请自行承担使用风险**，并严格遵循每一步骤。

我不会对您的设备因任何原因变砖负责，除非您愿意打钱：）

**如果您不熟悉平板改装、分区表操作或对设备变砖感到极度不安，请立即关闭此页面！您已经收到警告，任何后果自负！再次强调，您已收到警告！**

---

## 📊 功能状态（摘要）

| 类别   | 功能       | 状态     | 备注                     |
|--------|------------|----------|--------------------------|
| 核心   | 刷写       | 正常     | 仅双系统                 |
| 核心   | 屏幕/触摸  | 正常     | 含休眠/亮度/触摸         |
| 核心   | 键盘/触摸板| 正常     | 内置物理键盘与触摸板     |
| 连接   | Wi-Fi      | 正常     | 5GHz 不稳定，Wi-Fi6 不可用 |
| 连接   | 蓝牙       | 正常     | 偶尔不稳定               |
| 多媒体 | 音频/相机  | 正常     | 相机效果劣于 Android     |
| 传感器 | 全部       | 正常     | 自动旋转/亮度/霍尔等     |
| 手写笔 | 支持       | 故障     | 开发中                   |

> 完整功能状态表请查阅 [Wiki 首页](https://github.com/code002-2/Xiaomi-pad-6s-pro-Linux/wiki/%E9%A6%96%E9%A1%B5)

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
| [📥 安装指南（双系统）](https://github.com/code002-2/Xiaomi-pad-6s-pro-Linux/wiki/安装指南) | 分区、刷写 rootfs 与 boot 镜像，首次扩容 |
| [🔄 切换操作系统](https://github.com/code002-2/Xiaomi-pad-6s-pro-Linux/wiki/切换操作系统) | Android ↔ Linux 的无缝切换方法           |
| [⌨️ 官方键盘支持](https://github.com/code002-2/Xiaomi-pad-6s-pro-Linux/wiki/官方键盘支持) | Pogo Pin 键盘认证服务配置                |
| [📡 传感器支持](https://github.com/code002-2/Xiaomi-pad-6s-pro-Linux/wiki/传感器支持) | 加速度计、光线传感器等服务启用           |
| [🧩 推荐的 GNOME 扩展](https://github.com/code002-2/Xiaomi-pad-6s-pro-Linux/wiki/推荐的GNOME扩展) | 提升平板触摸体验的扩展列表               |

---

## 🎥 软件测试视频

【小米pad6spro debian hangover wine+dxvk测试-哔哩哔哩】 https://b23.tv/90orqIS

【小米pad6spro debian蓝牙手柄+vulkan小游戏测试-哔哩哔哩】 https://b23.tv/fjTWYWZ

【小米pad6spro Debian启动！-哔哩哔哩】 https://b23.tv/cWQmge0

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

**谨慎操作 – 祝使用愉快！**
