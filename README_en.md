# Xiaomi Pad 6S Pro Linux Port

[中文](README.md) | **English**

Documentation for the Linux port to the Xiaomi Pad 6S Pro 12.4 (SM8550, codename "sheng"): where to get flashable `rootfs` / `boot` images, feature status, and installation / usage guides.

## ⚠️ Disclaimer

Flashing is risky — proceed with caution. No warranty of any kind is provided, and **you use any file in this repository entirely at your own risk**, including but not limited to:

- Bricking the device or losing the recovery partition
- Hardware damage (storage, power management, display IC, CPU, …)
- Anything that follows from forgetting to boot back into Android, such as a missed alarm

If you are not comfortable modifying your tablet or its partition table, or if bricking the device worries you, stop now. **You are on your own.**

---

## 📊 Feature status

| Category | Feature | Status | Notes |
|------|------|------|------|
| Core | System flashing | ✅ Works | Multiple distributions supported |
| Core | Display / touch | ✅ Works | Including suspend and brightness |
| Core | Keyboard / touchpad | ⚠️ Partial | Official keyboard sometimes needs the Pogo pins reconnected |
| Connectivity | Wi-Fi | ✅ Works | Some regions require setting the regulatory domain |
| Connectivity | Bluetooth | ✅ Works | |
| Connectivity | USB Type-C | ⚠️ Partial | Conflicts with the keyboard Pogo pins |
| Multimedia | Audio / camera | ✅ Works | Camera quality is lower than on Android |
| Sensors | All | ✅ Works | Auto-rotation, ambient light, hall sensor, … |
| Stylus | Testing | ✅ Usable | Includes a stylus status indicator |
| Fingerprint | Testing | ✅ Usable | FPC1553 TEE driver |

> For the full component status table, see the [postmarketOS Wiki](https://wiki.postmarketos.org/wiki/Xiaomi_Pad_6S_Pro_12.4_(xiaomi-sheng)).

---

## 📦 Supported distributions

| Distribution | Desktop | Status | Build repository |
|--------|---------|------|---------|
| Debian 13 (Trixie) | GNOME, KDE | Stable | [ianchb/debian-sheng](https://github.com/ianchb/debian-sheng) |
| Ubuntu 26.10 / 26.04 / 25.10 | GNOME, KDE | Testing | [code002-2/ubuntu-sheng](https://github.com/code002-2/ubuntu-sheng) |
| Arch Linux ARM | GNOME, KDE | Testing | [code002-2/archlinux-sheng](https://github.com/code002-2/archlinux-sheng) |
| Fedora 44 | GNOME, KDE | Experimental | [mumuxiao722/fedora-sheng](https://github.com/mumuxiao722/fedora-sheng) |
| NixOS 25.05 | GNOME | Experimental | [DotRedstone/nixos-sheng](https://github.com/DotRedstone/nixos-sheng) |
| postmarketOS | Plasma, GNOME, Plasma Mobile, Lomiri | Testing (unofficial) | [alghiffaryfa19/sheng-pmos-builds](https://github.com/alghiffaryfa19/sheng-pmos-builds) |
| Armbian | GNOME / KDE / XFCE, … (minimal available) | Community maintained (CSC) | [armbian/build](https://github.com/armbian/build) |
| Armada (SteamOS-like, with Steam / FEX / Proton) | KDE Plasma + Game Mode | Experimental (prototype) | [code002-2/armada-sheng](https://github.com/code002-2/armada-sheng) |

---

## 📖 Guides

All installation, configuration and dual-boot steps live in the [`docs/`](docs/) directory ([中文索引](docs/README.md)):

| Guide | Description |
|------|------|
| [📥 Installation](docs/en/installation.md) | Partitioning, flashing the rootfs and boot images (dual-boot / single-boot) |
| [🔄 Switching OS](docs/en/switching-os.md) | Seamless Android ↔ Linux switching |
| [⌨️ Official keyboard support](docs/en/keyboard.md) | Pogo Pin keyboard authentication service |
| [📡 Sensor support](docs/en/sensors.md) | Enabling the sensor services |
| [🔊 Audio fix](docs/en/audio-fix.md) | Audio / speaker troubleshooting |
| [🧩 Recommended GNOME extensions](docs/en/gnome-extensions.md) | Better touch experience on a tablet |
| [🎮 Steam installation](docs/en/steam.md) | Native ARM64 Steam setup |
| [🎮 Armada flashing guide](https://github.com/code002-2/armada-sheng/blob/main/docs/flashing-xiaomi-sheng.md) | Flashing Armada, a SteamOS-like system (Steam / FEX / Proton) |
| [🐧 Armbian build guide](https://docs.armbian.com/Developer-Guide_Build-Preparation/) | Building images with [armbian/build](https://github.com/armbian/build) |

---

## 🚀 Quick install

1. Unlock the bootloader and make sure only Android is installed
2. Get the rootfs and boot images: this repository's [Releases](https://github.com/code002-2/Xiaomi-pad-6s-pro-Linux/releases), or the build repository of your distribution (see the "Supported distributions" table above)
3. Repartition with TWRP and `parted` (delete `userdata`, create `userdata` + `linux`)
4. Flash the images: `fastboot flash boot_b` and `fastboot flash linux`
5. Set slot B active and reboot
6. After the first boot, expand the filesystem with `sudo resize2fs /dev/sda30`

> Read the [Installation guide](docs/en/installation.md) before you start.

---

## ❤️ Credits

- [@map220v](https://github.com/map220v) — mainline kernel development and device drivers
- [@ianchb](https://github.com/ianchb) — MIPPS fast-charging patches, stylus charging
- [@alghiffaryfa19](https://github.com/alghiffaryfa19) — upstream project
- [@code002-2](https://github.com/code002-2) — further development and maintenance

---

## 📢 Community

[![Telegram](https://img.shields.io/badge/Follow-Telegram-blue.svg?logo=telegram)](https://t.me/Pad_6S_Pro_Linux_Chat)

---

**Proceed with caution — enjoy!**
