#!/bin/bash
set -euo pipefail

# =============================================================================
# build-ubuntu26-rootfs.sh — Ubuntu 26.04 rootfs builder (refactored)
# =============================================================================
source "$(dirname "$0")/lib/rootfs-common.sh"

# --- Distro-specific configuration ---
IMAGE_SIZE="8G"
UUID="ee8d3593-59b1-480e-a3b6-4fefb17ee7d8"
UBUNTU_SUITE="resolute"
UBUNTU_MIRROR="https://mirrors.tuna.tsinghua.edu.cn/ubuntu"

# --- Password configuration (override via env vars) ---
ROOT_PASS="${ROOT_PASS:-1234}"
USER_PASS="${USER_PASS:-luser}"
USER_NAME="${USER_NAME:-luser}"

# --- Argument parsing ---
usage() {
    echo "用法: $0 <kernel_version> <desktop_environment> [boot_mode]"
    echo "desktop_environment: gnome, kde 或 xfce"
    echo "boot_mode: dual 或 single (默认 dual)"
    exit 1
}

if [ $# -lt 2 ] || [ $# -gt 3 ]; then usage; fi
if [ "$(id -u)" -ne 0 ]; then echo "请使用root权限运行"; exit 1; fi

KERNEL=$1
DESKTOP_ENV=$2
BOOT_MODE=${3:-dual}

if [[ ! "$DESKTOP_ENV" =~ ^(gnome|kde|xfce)$ ]]; then
    echo "错误: desktop_environment 必须是 gnome, kde 或 xfce"
    exit 1
fi

if [[ ! "$BOOT_MODE" =~ ^(dual|single)$ ]]; then
    echo "错误: boot_mode 必须是 dual 或 single"
    exit 1
fi

TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
ROOTFS_IMG="ubuntu26_${DESKTOP_ENV}_${TIMESTAMP}.img"

echo "=========================================="
echo "开始构建 Ubuntu 26.04 LTS RootFS"
echo "桌面环境: $DESKTOP_ENV"
echo "内核版本: $KERNEL"
echo "=========================================="

# Pre-flight checks
preflight_checks 10240

# Step 1: Create image
create_image "$IMAGE_SIZE" "$ROOTFS_IMG" "$UUID"
setup_chroot_mounts "$ROOTDIR"
trap_teardown "$ROOTDIR"

# Step 2: Bootstrap
debootstrap --arch=arm64 "$UBUNTU_SUITE" "$ROOTDIR" "$UBUNTU_MIRROR"

# Step 3: Apt sources
printf "deb %s %s main restricted universe multiverse\n" "$UBUNTU_MIRROR" "$UBUNTU_SUITE" > "$ROOTDIR/etc/apt/sources.list"
printf "deb %s %s-updates main restricted universe multiverse\n" "$UBUNTU_MIRROR" "$UBUNTU_SUITE" >> "$ROOTDIR/etc/apt/sources.list"
printf "deb %s %s-backports main restricted universe multiverse\n" "$UBUNTU_MIRROR" "$UBUNTU_SUITE" >> "$ROOTDIR/etc/apt/sources.list"
printf "deb %s %s-security main restricted universe multiverse\n" "$UBUNTU_MIRROR" "$UBUNTU_SUITE" >> "$ROOTDIR/etc/apt/sources.list"

chroot "$ROOTDIR" apt update

# Step 4: Base packages
chroot "$ROOTDIR" apt install -y --no-install-recommends \
    systemd sudo vim-tiny wget curl \
    network-manager openssh-server \
    wpasupplicant dbus kmod initramfs-tools

# Step 5: Kernel injection
if ls *.deb 1> /dev/null 2>&1; then
    cp *.deb "$ROOTDIR/tmp/"
    chroot "$ROOTDIR" bash -c "apt install -y /tmp/*.deb || true"

    KERNEL_MODULE_DIR=$(detect_kernel_module_dir "$ROOTDIR")
    if [ -n "$KERNEL_MODULE_DIR" ]; then
        echo "动态识别到真实内核版本目录: $KERNEL_MODULE_DIR"
        chroot "$ROOTDIR" /sbin/depmod -a "$KERNEL_MODULE_DIR" || true
    fi
else
    echo "错误: 当前目录下未找到任何 .deb 内核包，无法生成可启动 rootfs！" >&2
    exit 1
fi

# Step 6: Locale & hostname
chroot "$ROOTDIR" bash -c "echo 'LANG=en_US.UTF-8' > /etc/default/locale"
chroot "$ROOTDIR" locale-gen en_US.UTF-8
echo "ubuntu26-${DESKTOP_ENV}" > "$ROOTDIR/etc/hostname"

# Step 7: Users — 使用公共库
setup_users "$ROOTDIR" "$ROOT_PASS" "$USER_NAME" "$USER_PASS" "sudo,audio,video,render,input,plugdev"

# Step 8: Desktop environment
if [ "$DESKTOP_ENV" = "gnome" ]; then
    chroot "$ROOTDIR" apt install -y --no-install-recommends ubuntu-desktop-minimal gnome-terminal firefox gdm3
elif [ "$DESKTOP_ENV" = "kde" ]; then
    chroot "$ROOTDIR" apt install -y --no-install-recommends plasma-desktop sddm konsole firefox plasma-workspace systemsettings discover packagekit
elif [ "$DESKTOP_ENV" = "xfce" ]; then
    chroot "$ROOTDIR" apt install -y --no-install-recommends xfce4 xfce4-terminal lightdm lightdm-gtk-greeter firefox mousepad thunar
fi

# Step 9: DM autologin — 使用公共库
setup_autologin "$ROOTDIR" "$DESKTOP_ENV" "$USER_NAME"

# Handle sddm user group membership for KDE
if [ "$DESKTOP_ENV" = "kde" ]; then
    if chroot "$ROOTDIR" id -u sddm >/dev/null 2>&1; then
        chroot "$ROOTDIR" usermod -aG video,render,input sddm || true
    fi
    # Plasma screen blanking workaround (KDE-specific)
    mkdir -p "$ROOTDIR/etc/xdg"
    printf "[PowerManagement]\nScreenBlanking=false\nDisplaySleep=0\n" > "$ROOTDIR/etc/xdg/plasmarc"
fi

chroot "$ROOTDIR" systemctl set-default graphical.target

# Step 10: Hardware quirks
setup_getty_ttyMSM0 "$ROOTDIR"
setup_systemd_resolved_symlink "$ROOTDIR"
configure_touchscreen "$ROOTDIR"
fix_wifi_firmware "$ROOTDIR"

chroot "$ROOTDIR" apt install -y qrtr-tools || true
chroot "$ROOTDIR" systemctl enable qrtr-ns || true

# Step 11: fstab & cleanup
generate_fstab "$ROOTDIR" "$BOOT_MODE"
chroot "$ROOTDIR" apt clean
chroot "$ROOTDIR" rm -rf /tmp/*.deb
teardown_mounts "$ROOTDIR"

# Step 12: Pack
apply_fs_uuid "$UUID" "$ROOTFS_IMG"
echo "原始镜像生成完成: $ROOTFS_IMG"
echo "正在转换为 Sparse 镜像..."
pack_sparse_image "$ROOTFS_IMG" "ubuntu26_${DESKTOP_ENV}_${TIMESTAMP}.7z"

echo "Ubuntu 构建成功！"
