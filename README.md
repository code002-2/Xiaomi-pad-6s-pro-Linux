# Xiaomi Pad 6S Pro Linux Port

**中文** | [English](README_en.md)

小米平板 6S Pro 12.4 (SM8550, 代号 "sheng") 的 Linux 移植项目文档：收录各发行版可直接刷写的 rootfs 与 boot 镜像发布信息、功能状态与安装/使用指南。

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
| 手写笔 | 测试 | ✅ 可用 | 含触控笔状态指示器 |
| 指纹 | 测试 | ✅ 可用 | FPC1553 TEE 驱动 |

> 完整功能状态表请查阅 [PostmarketOS Wiki](https://wiki.postmarketos.org/wiki/Xiaomi_Pad_6S_Pro_12.4_(xiaomi-sheng))

---

## 📦 支持的发行版

| 发行版 | 桌面环境 | 状态 | 构建仓库 |
|--------|---------|------|---------|
| Debian 13 (Trixie) | GNOME, KDE | 稳定 | [ianchb/debian-sheng](https://github.com/ianchb/debian-sheng) |
| Ubuntu 26.10 / 26.04 / 25.10 | GNOME, KDE | 测试 | [code002-2/ubuntu-sheng](https://github.com/code002-2/ubuntu-sheng) |
| Arch Linux ARM | GNOME, KDE | 测试 | [code002-2/archlinux-sheng](https://github.com/code002-2/archlinux-sheng) |
| Fedora 44 | GNOME, KDE | 实验 | [mumuxiao722/fedora-sheng](https://github.com/mumuxiao722/fedora-sheng) |
| NixOS 25.05 | GNOME | 实验 | [DotRedstone/nixos-sheng](https://github.com/DotRedstone/nixos-sheng) |
| postmarketOS | Plasma, GNOME, Plasma Mobile, Lomiri | 测试（unofficial） | [alghiffaryfa19/sheng-pmos-builds](https://github.com/alghiffaryfa19/sheng-pmos-builds) |
| Armbian | GNOME / KDE / XFCE 等（可只装 minimal） | 社区维护（CSC） | [armbian/build](https://github.com/armbian/build) |
| Armada（SteamOS 类，含 Steam / FEX / Proton） | KDE Plasma + 游戏模式 | 实验（原型） | [code002-2/armada-sheng](https://github.com/code002-2/armada-sheng) |
| **SteamOS**（Valve Steam Frame 官方镜像为底包） | KDE Plasma | 测试（v0.3.0） | [code002-2/steamos-sheng](https://github.com/code002-2/steamos-sheng) |

> SteamOS 版直接用 Valve 的 Steam Frame 官方恢复镜像当底包（SteamOS holo，aarch64），再注入 sheng 的内核 / 固件 / 设备层，所以**刷写方式与上表其它发行版不同**：
> `fastboot flash userdata rootfs.img` + `fastboot flash boot_b boot.img`，无需自己重分区。详见 [steamos-sheng 仓库说明](https://github.com/code002-2/steamos-sheng)。

---

## 📖 详细指南

所有安装、配置、切换系统的详细步骤都在 [`docs/`](docs/) 目录中（[English](docs/en/README.md)）：

| 指南 | 说明 |
|------|------|
| [📥 安装指南](docs/安装指南.md) | 分区、刷写 rootfs 与 boot 镜像（双系统 / 单系统） |
| [🔄 切换操作系统](docs/切换操作系统.md) | Android ↔ Linux 无缝切换 |
| [⌨️ 官方键盘支持](docs/官方键盘支持.md) | Pogo Pin 键盘认证服务 |
| [📡 传感器支持](docs/传感器支持.md) | 启用各项传感器服务 |
| [🔊 声音修复](docs/声音修复.md) | 音频 / 扬声器问题排查 |
| [🧩 GNOME 扩展推荐](docs/推荐的GNOME扩展.md) | 提升平板触摸体验 |
| [🎮 Steam 安装](docs/steam.md) | Linux ARM64 Steam 教程 |
| [🎮 Armada 刷写指南](https://github.com/code002-2/armada-sheng/blob/main/docs/flashing-xiaomi-sheng.md) | 刷入 SteamOS 类系统 Armada（含 Steam / FEX / Proton） |
| [🎮 SteamOS 刷写指南](https://github.com/code002-2/steamos-sheng) | 刷入 SteamOS（Steam Frame 官方镜像为底包，KDE Plasma） |
| [🐧 Armbian 构建指南](https://docs.armbian.com/Developer-Guide_Build-Preparation/) | 用 [armbian/build](https://github.com/armbian/build) 自行构建镜像 |

---

## 🚀 快速安装

1. 解锁 bootloader，确保仅有 Android 系统
2. 获取 rootfs 与 boot 镜像：本仓库 [Releases](https://github.com/code002-2/Xiaomi-pad-6s-pro-Linux/releases)，或对应发行版的构建仓库（见上方「支持的发行版」表）
3. 通过 TWRP 和 `parted` 重分区（删除 userdata，新建 userdata + linux）
4. 刷写镜像：`fastboot flash boot_b` 和 `fastboot flash linux`
5. 激活槽位 B 并重启
6. 首次启动后执行 `sudo resize2fs /dev/sda30` 扩容

> 详细步骤请务必阅读 [安装指南](docs/安装指南.md)

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
