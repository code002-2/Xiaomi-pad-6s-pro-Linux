#!/bin/bash
set -euo pipefail

source "$(dirname "$0")/lib/rootfs-common.sh"

# --- Distro-specific configuration ---
IMAGE_SIZE="8G"
UUID="ee8d3593-59b1-480e-a3b6-4fefb17ee7d8"
DEBIAN_SUITE="beige"
DEBIAN_MIRROR="https://community-packages.deepin.com/beige/"

# --- Password configuration ---
ROOT_PASS="${ROOT_PASS:-1234}"
USER_PASS="${USER_PASS:-luser}"
USER_NAME="${USER_NAME:-luser}"

# --- Argument parsing ---
if [ $# -ne 2 ]; then
    echo "用法: $0 <distro_name> <kernel_version>"
    exit 1
fi
if [ "$(id -u)" -ne 0 ]; then echo "请使用root权限运行"; exit 1; fi

DISTRO=$1
KERNEL=$2
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
ROOTFS_IMG="deepin25_1_0_desktop_${TIMESTAMP}.img"

echo "=========================================="
echo "开始构建 Deepin 25.1.0 RootFS"
echo "内核版本: $KERNEL"
echo "=========================================="

# Step 1: Create image
create_image "$IMAGE_SIZE" "$ROOTFS_IMG" "$UUID"

# Step 2: Bootstrap (Deepin uses a Debian script symlink)
if [ ! -f "/usr/share/debootstrap/scripts/${DEBIAN_SUITE}" ]; then
    ln -sf /usr/share/debootstrap/scripts/sid "/usr/share/debootstrap/scripts/${DEBIAN_SUITE}"
fi

# Import Deepin keyring if available
if [ -f /usr/share/keyrings/deepin-archive-keyring.gpg ]; then
    mkdir -p "$ROOTDIR/etc/apt/trusted.gpg.d"
    cp /usr/share/keyrings/deepin-archive-keyring.gpg "$ROOTDIR/etc/apt/trusted.gpg.d/deepin.gpg"
fi

debootstrap --arch=arm64 "$DEBIAN_SUITE" "$ROOTDIR" "$DEBIAN_MIRROR"

setup_chroot_mounts "$ROOTDIR"

# APT sources (removed [trusted=yes])
printf "deb %s %s main commercial community\n" "$DEBIAN_MIRROR" "$DEBIAN_SUITE" > "$ROOTDIR/etc/apt/sources.list"
setup_dns "$ROOTDIR" 8.8.8.8 1.1.1.1 114.114.114.114

chroot "$ROOTDIR" apt update

# Kernel injection
if ls *.deb 1> /dev/null 2>&1; then
    cp *.deb "$ROOTDIR/tmp/"
    chroot "$ROOTDIR" bash -c "apt install -y /tmp/*.deb || apt-get install -f -y"
fi

# Base packages
chroot "$ROOTDIR" apt install -y --no-install-recommends \
    deepin-keyring systemd systemd-resolved sudo vim-tiny wget curl network-manager wpasupplicant dbus locales initramfs-tools

# Restore DNS
setup_dns "$ROOTDIR" 8.8.8.8 1.1.1.1

# Chinese locale
echo "正在注入原生中文语言环境..."
chroot "$ROOTDIR" bash -c "echo 'LANG=zh_CN.UTF-8' > /etc/default/locale"
chroot "$ROOTDIR" sed -i 's/# zh_CN.UTF-8 UTF-8/zh_CN.UTF-8 UTF-8/' /etc/locale.gen
chroot "$ROOTDIR" locale-gen zh_CN.UTF-8

echo "deepin-sheng" > "$ROOTDIR/etc/hostname"

# Desktop environment
echo "正在拉取 Deepin 原生完整桌面生态与 3D 驱动..."
chroot "$ROOTDIR" bash -c "apt install -y deepin-desktop-environment-core dde-session-shell dde-dock dde-launcher dde-desktop dde-control-center lightdm xwayland deepin-kwin-wayland xserver-xorg xinit fonts-noto-cjk fonts-wqy-microhei libgl1-mesa-dri libglx-mesa0 libegl-mesa0 mesa-vulkan-drivers mesa-utils || apt install -y deepin-desktop-environment-core dde-session-shell lightdm xwayland deepin-kwin-wayland xserver-xorg xinit fonts-noto-cjk fonts-wqy-microhei libgl1-mesa-dri libglx-mesa0 libegl-mesa0 mesa-vulkan-drivers mesa-utils"

# Snapdragon firmware
echo "正在从 Kernel.org 上游提取骁龙专属闭源固件..."
mkdir -p "$ROOTDIR/tmp/linux-fw"
git clone --depth 1 --filter=blob:none --sparse https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git "$ROOTDIR/tmp/linux-fw"
git -C "$ROOTDIR/tmp/linux-fw" sparse-checkout set qcom
mkdir -p "$ROOTDIR/lib/firmware/"
cp -a "$ROOTDIR/tmp/linux-fw/qcom" "$ROOTDIR/lib/firmware/"
rm -rf "$ROOTDIR/tmp/linux-fw"

# Step 3: Users
setup_users "$ROOTDIR" "$ROOT_PASS" "$USER_NAME" "$USER_PASS" "sudo,audio,video,render,input"

# Step 4: Hardware quirks
setup_getty_ttyMSM0 "$ROOTDIR"

# WiFi fix
fix_wifi_firmware "$ROOTDIR" "lib/firmware/ath12k/WCN7850/hw2.0"

chroot "$ROOTDIR" systemctl enable systemd-resolved
setup_systemd_resolved_symlink "$ROOTDIR"

configure_touchscreen "$ROOTDIR"

# Wayland/X11 profile script
echo "配置全局 Wayland/X11 智能引导引擎..."
cat > "$ROOTDIR/etc/profile.d/wayland-force.sh" <<EOF
export XDG_SESSION_TYPE=wayland
export QT_QPA_PLATFORM="wayland;xcb"
export MOZ_ENABLE_WAYLAND=1
export WLR_NO_HARDWARE_CURSORS=1
EOF
chmod +x "$ROOTDIR/etc/profile.d/wayland-force.sh"

# LightDM autologin with smart Wayland detection
mkdir -p "$ROOTDIR/etc/lightdm/lightdm.conf.d"
cat > "$ROOTDIR/etc/lightdm/lightdm.conf.d/12-autologin.conf" <<EOF
[Seat:*]
autologin-user=$USER_NAME
autologin-user-timeout=0
EOF

WAYLAND_SESSION=$(ls "$ROOTDIR/usr/share/wayland-sessions/"*.desktop 2>/dev/null | head -n 1 | awk -F'/' '{print $NF}' | sed 's/\.desktop//' || true)
if [ -n "$WAYLAND_SESSION" ]; then
    echo "user-session=$WAYLAND_SESSION" >> "$ROOTDIR/etc/lightdm/lightdm.conf.d/12-autologin.conf"
    echo "智能探测成功！检测到 Wayland 会话名为: $WAYLAND_SESSION"
else
    echo "user-session=dde-x11" >> "$ROOTDIR/etc/lightdm/lightdm.conf.d/12-autologin.conf"
    echo "警告：未检测到 Wayland 会话，强制回退至 X11"
fi

chroot "$ROOTDIR" systemctl enable lightdm
chroot "$ROOTDIR" systemctl set-default graphical.target
chroot "$ROOTDIR" systemctl mask deepin-login-sound.service || true
chroot "$ROOTDIR" systemctl mask deepin-login-sound-service.service || true
chroot "$ROOTDIR" bash -c "sed -i 's/quiet splash//g' /etc/default/grub" 2>/dev/null || true

# Force MSM GPU modules in initramfs
echo "msm" >> "$ROOTDIR/etc/initramfs-tools/modules"
echo "gpu_sched" >> "$ROOTDIR/etc/initramfs-tools/modules"
echo "panel_edp" >> "$ROOTDIR/etc/initramfs-tools/modules"

# Step 5: fstab & cleanup
generate_fstab "$ROOTDIR" "dual"
echo "强制重新生成 initramfs 引导镜像..."
chroot "$ROOTDIR" bash -c "update-initramfs -u -k all"
chroot "$ROOTDIR" apt clean
chroot "$ROOTDIR" rm -rf /tmp/*.deb
teardown_mounts "$ROOTDIR"

# Step 6: Pack (Deepin uses plain 7z, no sparse conversion)
echo "正在生成最终 7z 压缩包..."
7z a "deepin25_1_0_desktop_${TIMESTAMP}.7z" "$ROOTFS_IMG" -mx=1
rm -f "$ROOTFS_IMG"

echo "🎉 纯血 Deepin 固件修复版构建完成！"
