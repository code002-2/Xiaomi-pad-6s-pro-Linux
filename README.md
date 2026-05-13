# 警告
我们不对以下情况负责：变砖的设备、丢失的恢复分区、死掉的小米流水线工人、损坏的存储卡、损坏的电源管理芯片、损坏的内存、损坏的显示驱动芯片、损坏的CPU、任何小米的骚操作、死掉的猫狗、核战争，或者因为你忘记切回安卓系统而导致闹钟没响被炒鱿鱼。

这里的所有文件均由其他用户贡献，你将找到一份指南，里面包含我们设法搞定的可用文件。这是一个精细的过程，请自行承担风险，并仔细遵循所有步骤。

**如果你不习惯改装你的平板或其分区表，或者你非常害怕设备变砖，请立即离开！！！你已经收到警告，如果你的设备变砖，后果自负！！！再次强调，你已经收到警告！！！**

## 状态
| 类别            | 功能                | 状态     | 描述 |
|-----------------|--------------------|----------|------|
| 核心            | 刷写               | 正常     | only 双系统 |
| 核心            | USB 网络           | 正常     | 通过 USB 将设备连接到电脑后，可以通过 telnet (initramfs) 或 SSH (启动后的系统) 连接。 |
| 核心            | 电池               | 正常     | 充电及电量报告正常工作 不兼容小米原装充电器 |
| 核心            | 屏幕               | 正常     | 显示是否工作；最好包含睡眠模式和亮度控制。 |
| 核心            | 触摸屏             | 正常     | — |
| 核心            | 键盘               | 正常     | 内置物理键盘正常工作。 |
| 核心            | 触摸板             | 正常     | 内置触摸板正常工作。 |
| 核心            | 手写笔             | 故障     | 开发中 |
| 多媒体          | 3D 加速            | 正常     | — |
| 多媒体          | 音频               | 正常     | 音频播放 麦克风 耳机及按键正常工作 |
| 多媒体          | 相机               | 正常     | 正常工作 尽管效果不如安卓 |
| 多媒体          | 相机闪光灯         | 正常     | 正常工作 |
| 连接            | Wi-Fi              | 正常     | 5Gwifi似乎有些问题 随缘连上 wifi6应该是用不了 |
| 连接            | 蓝牙               | 正常     | 有些不稳定 |
| 连接            | NFC                | 未测试   | 近场通信 |
| 杂项            | FDE                | 故障     | 全盘加密及使用 unl0kr 解锁。 |
| 杂项            | USB OTG            | 正常     | USB On-The-Go 或 USB-C 角色切换。 |
| 杂项            | HDMI/DP            | 正常     | 通过 HDMI 或 DisplayPort 输出视频和音频。 |
| 传感器          | 加速度计           | 正常     | 在多数界面中处理自动屏幕旋转。 |
| 传感器          | 磁力计             | 正常     | 测量地球磁场的传感器。 |
| 传感器          | 环境光             | 正常     | 测量光照强度；在多数界面中用于自动调暗屏幕。 |
| 传感器          | 接近传感器         | 正常     | — |
| 传感器          | 霍尔效应           | 正常     | 测量磁场；通常用作翻盖皮套传感器。 |

# 安装指南
请仔细遵循本指南

1. 确保您已解锁设备的引导加载程序，并且只安装了安卓操作系统。
2. 从Github Action下载所需的 rootfs 和 boot 镜像。

# 单系统启动
也许以后会有。

# 双系统启动
1. 启动到 TWRP
    ```bash
    adb reboot recovery
    ```

2. 下载本仓库中的 parted 文件。
3. 将 parted 文件推送到安卓存储
    ```bash
    adb push <path/to/parted> /sdcard
    ```
4. 进入 adb shell
    ```bash
    adb shell
    ```
5. 创建 Linux 分区
    ```bash
    chmod +x /sdcard/parted
    /sdcard/parted /dev/block/sda
    ```
6. 删除 userdata 分区，记下其编号（最左边），在我这里 userdata 是第 29
    ```bash
    print
    rm 29
    ```
7. 创建 userdata 和 Linux 分区（userdata 128GB，Linux 128GB）
    ```bash
    mkpart userdata ext4 12.7GB 140.7GB
    mkpart linux ext4 140.7GB -0MB
    ```

8. 检查已创建的分区
    ```bash
    print
    ```

9. 你会看到 29 为 userdata，30 为 linux
10. 退出 parted
    ```bash
    quit
    ```
11. 退出 shell
    ```bash
    exit
    ```
12. 启动到 bootloader
    ```bash
    adb reboot bootloader
    ```

13. 擦除 dtbo
    ```bash
    fastboot erase dtbo_b
    ```

14. 刷写 boot 镜像
    ```bash
    fastboot flash boot_b boot-*.img
    ```

15. 刷写 rootfs 镜像
    ```bash
    fastboot flash linux rootfs*.img
    ```

16. 激活槽位 B
    ```bash
    fastboot set_active b
    ```

17. 重启
    ```bash
    fastboot reboot
    ```

# 切换操作系统
1. 从安卓切换到 Linux
    - 图形界面方法（需要 root）
        - 从此处下载应用 [此处](https://github.com/capntrips/BootControl/releases)
        - 安装应用
        - 打开应用
        - 激活槽位 B 并重启

    - Bootloader 方法（无需 root，需要电脑）
        - 启动到 bootloader
        - 激活槽位 B
        ```bash
        fastboot set_active b
        fastboot reboot
        ```

2. 从 Linux 切换到安卓
    - Bootloader 方法（需要电脑 / [来自另一台安卓设备的 Termux ADB-Fastboot](https://github.com/offici5l/termux-adb-fastboot)）
        - 启动到 bootloader
        - 激活槽位 A
        ```bash
        fastboot set_active a
        fastboot reboot
        ```

    我不推荐使用 qbootctl，因为它可能导致设备变砖。

# 🔐 登录凭证
默认系统凭证

用户名: luser
密码: luser

# 官方键盘
请仔细遵循指南

1. 检查服务
    ```bash
    sudo systemctl status sheng-devauth
    ```

2. 如果未激活
    ```bash
    sudo systemctl enable sheng-devauth
    sudo systemctl start sheng-devauth
    ```

3. 重新插上键盘的 Pogo Pin
4. 再次检查服务
    ```bash
    sudo systemctl status sheng-devauth
    ```
5. 如果你看到 "Sent pad token to kernel driver!"，表示键盘已就绪。
6. 每次启动后都需要重新插拔一下针脚。该服务用于向驱动程序发送令牌，因为键盘需要身份验证。

# 传感器
请仔细遵循指南

1. 检查服务
    ```bash
    sudo systemctl status iio-sensor-proxy
    sudo systemctl status adsprpcd-sensorspd
    ```

2. 如果未激活
    ```bash
    sudo systemctl enable iio-sensor-proxy
    sudo systemctl start iio-sensor-proxy
    sudo systemctl enable adsprpcd-sensorspd
    sudo systemctl start adsprpcd-sensorspd
    ```

3. 监控传感器
    ```bash
    monitor-sensor
    ```

4. 如果你看到每个传感器的数值发生变化，说明传感器工作正常。

# Gnome 扩展推荐

1. Auto Activities
2. Maximized by default actually reborn
3. Maximized Into Empty Workspace
4. Overview Background
5. Reorder Workspaces
6. TouchUp

这些扩展用于最大化平板上触摸屏的使用体验。
