# Xiaomi Pad 6S Pro Linux Port

[![GitHub Release](https://img.shields.io/github/v/release/code002-2/Xiaomi-pad-6s-pro-Linux?style=flat-square&logo=github&color=blue)](https://github.com/code002-2/Xiaomi-pad-6s-pro-Linux/releases)
[![Build Kernel](https://img.shields.io/github/actions/workflow/status/code002-2/Xiaomi-pad-6s-pro-Linux/kernel.yml?style=flat-square&logo=linux&label=Kernel%20Build)](https://github.com/code002-2/Xiaomi-pad-6s-pro-Linux/actions/workflows/kernel.yml)
[![Build Debian 13](https://img.shields.io/github/actions/workflow/status/code002-2/Xiaomi-pad-6s-pro-Linux/build-debian13.yml?style=flat-square&logo=debian&label=Debian%2013%20Rootfs)](https://github.com/code002-2/Xiaomi-pad-6s-pro-Linux/actions/workflows/build-debian13.yml)
[![Build Ubuntu 26](https://img.shields.io/github/actions/workflow/status/code002-2/Xiaomi-pad-6s-pro-Linux/build-ubuntu26.yml?style=flat-square&logo=ubuntu&label=Ubuntu%2026%20Rootfs)](https://github.com/code002-2/Xiaomi-pad-6s-pro-Linux/actions/workflows/build-ubuntu26.yml)
[![Build NixOS](https://img.shields.io/github/actions/workflow/status/code002-2/Xiaomi-pad-6s-pro-Linux/build-nixos.yml?style=flat-square&logo=nixos&label=NixOS%20Rootfs)](https://github.com/code002-2/Xiaomi-pad-6s-pro-Linux/actions/workflows/build-nixos.yml)


为小米平板 6S Pro 12.4 (SM8550, 代号 "sheng") 编译和打包 Linux 内核与 rootfs 镜像，支持多个主流发行版。

> 项目基于 [@alghiffaryfa19](https://github.com/alghiffaryfa19) 的上游项目二次开发。

## ⚠️ 免责声明

刷机有风险，操作需谨慎。本项目不提供任何保修，使用本仓库的任何文件均**自行承担风险**。包括但不限于：

- 设备变砖、恢复分区丢失
- 硬件损坏（存储、电源管理、显示芯片、CPU 等）
- 因忘记切回 Android 导致闹钟未响等一切后果

如果您对平板改装、分区表操作不熟悉，或对设备变砖感到不安，请立即停止。**任何后果自负。**

---

## 📊 功能状态

| 类别 | 功能 | 状态 | 备注 |
|------|------|------|------|
| 核心 | 系统刷写 | ✅ 正常 | 多发行版支持 |
| 核心 | 屏幕/触摸 | ✅ 正常 | 含休眠/亮度/触摸 |
| 核心 | 键盘/触摸板 | ⚠️ 部分 | 官方键盘需重新连接触点 |
| 连接 | Wi-Fi | ✅ 正常 | 部分地区需设置区域码 |
| 连接 | 蓝牙 | ✅ 正常 | |
| 连接 | Type-C | ⚠️ 部分 | 与键盘触点冲突 |
| 多媒体 | 音频/相机 | ✅ 正常 | 相机效果劣于 Android |
| 传感器 | 全部 | ✅ 正常 | 自动旋转/亮度/霍尔等 |
| 手写笔 | 测试 | ❌ 故障 | 仅充电可用 |

> 完整功能状态表请查阅 [PostmarketOS Wiki](https://wiki.postmarketos.org/wiki/Xiaomi_Pad_6S_Pro_12.4_(xiaomi-sheng))

---

## 📦 支持的发行版

| 发行版 | 构建脚本 | 桌面环境 | 状态 |
|--------|---------|---------|------|
| Debian 13 (Trixie) | `sheng-rootfs_build.sh` | GNOME, KDE | 稳定 |
| Ubuntu 26.04 | `build-ubuntu26-rootfs.sh` | GNOME, KDE, XFCE | 测试 |
| Arch Linux ARM | `sheng-arch-rootfs_build.sh` | GNOME, KDE | 测试 |
| Fedora 44 | `sheng-fedora-rootfs_build.sh` | GNOME, KDE | 实验 |
| NixOS 25.05 | `sheng-nixos-rootfs_build.sh` | Niri | 实验 |

---

## 🔐 默认凭据

| 账户 | 用户名 | 密码 |
|------|--------|------|
| 普通用户 | `luser` | `luser` |
| 管理员 (root) | `root` | `1234` |

> 首次登录后请立即修改密码。可通过环境变量 `ROOT_PASS`、`USER_PASS`、`USER_NAME` 自定义。

---

## 📖 详细指南

所有安装、配置、切换系统的详细步骤均在 **Wiki** 中：

| 指南 | 说明 |
|------|------|
| [📥 安装指南](https://github.com/code002-2/Xiaomi-pad-6s-pro-Linux/wiki/安装指南) | 分区、刷写 rootfs 与 boot 镜像 |
| [🔄 切换操作系统](https://github.com/code002-2/Xiaomi-pad-6s-pro-Linux/wiki/切换操作系统) | Android ↔ Linux 无缝切换 |
| [⌨️ 官方键盘支持](https://github.com/code002-2/Xiaomi-pad-6s-pro-Linux/wiki/官方键盘支持) | Pogo Pin 键盘认证服务 |
| [📡 传感器支持](https://github.com/code002-2/Xiaomi-pad-6s-pro-Linux/wiki/传感器支持) | 启用各项传感器服务 |
| [🧩 GNOME 扩展推荐](https://github.com/code002-2/Xiaomi-pad-6s-pro-Linux/wiki/推荐的GNOME扩展) | 提升平板触摸体验 |
| [🎮 Steam 安装](https://github.com/code002-2/Xiaomi-pad-6s-pro-Linux/wiki/steam) | Linux ARM64 Steam 教程 |

---

## 🚀 快速安装

1. 解锁 bootloader，确保仅有 Android 系统
2. 从 [Releases](https://github.com/code002-2/Xiaomi-pad-6s-pro-Linux/releases) 下载 rootfs 和 boot 镜像
3. 通过 TWRP 和 `parted` 重分区（删除 userdata，新建 userdata + linux）
4. 刷写镜像：`fastboot flash boot_b` 和 `fastboot flash linux`
5. 激活槽位 B 并重启
6. 首次启动后执行 `sudo resize2fs /dev/sda30` 扩容

> 详细步骤请务必阅读 [安装指南 Wiki](https://github.com/code002-2/Xiaomi-pad-6s-pro-Linux/wiki/安装指南)

---

## 🛠️ 本地构建

### 前置条件

- Ubuntu 24.04 ARM64 (或等效环境)
- root 权限
- 工具: `debootstrap`, `mkbootimg`, `parted`, `img2simg`, `p7zip-full`, `docker` (Fedora)

### 构建 rootfs

```bash
sudo bash sheng-rootfs_build.sh debian-desktop 7.1 all all
# 参数: <distro-variant> <kernel_version> <boot_mode> <desktop_env>
```

### 自定义凭据

```bash
ROOT_PASS="myrootpass" USER_PASS="myuserpass" USER_NAME="myuser" \
sudo bash sheng-rootfs_build.sh debian-desktop 7.1 dual gnome
```

### 构建内核

内核支持 **Mainline**（主线）和 **Stable**（稳定）两个通道：

```bash
# Mainline 通道 (默认)
bash sheng-kernel_build.sh

# Stable 通道
KERNEL_CHANNEL=stable bash sheng-kernel_build.sh
```

### 指定内核通道构建 rootfs

rootfs 构建时会自动从对应通道的内核 Release 中下载 `.deb` 驱动包：

```bash
# 使用 mainline 内核 (默认)
sudo bash sheng-rootfs_build.sh debian-desktop 7.1 all all

# 使用 stable 内核
KERNEL_CHANNEL=stable sudo bash sheng-rootfs_build.sh debian-desktop 7.1 all all
```

在 CI 中，每个工作流都有 `kernel_channel` 输入项可选 mainline 或 stable。

### 本地构建 NixOS

```bash
# 需要先安装 Nix（推荐 nix-community/setup-nix 方式）
# 然后在 nixos/ 目录下验证 flake：
cd nixos
nix flake check

# 本地构建（需要 runner 上已安装 Nix）
sudo bash sheng-nixos-rootfs_build.sh nixos 7.1 all niri
```

---

## ❤️ 致谢

- [@map220v](https://github.com/map220v) — 主线内核开发与设备驱动
- [@ianchb](https://github.com/ianchb) — MIPPS 快充补丁、触控笔充电
- [@alghiffaryfa19](https://github.com/alghiffaryfa19) — 上游项目
- [@code002-2](https://github.com/code002-2) — 二次开发与维护

---

## 📢 社区

[![Telegram](https://img.shields.io/badge/Follow-Telegram-blue.svg?logo=telegram)](https://t.me/Pad_6S_Pro_Linux_Chat)

---

**谨慎操作 — 祝使用愉快！**
