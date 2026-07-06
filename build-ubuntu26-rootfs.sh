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
# Accepts 4 args from _rootfs-template.yml: $distro $KERNEL_VER $BOOT_MODE $DESKTOP_ENV
usage() {
    echo "Usage: $0 <distro> <kernel_version> <boot_mode> <desktop_environment>"
    echo "desktop_environment: gnome, kde, or xfce"
    echo "boot_mode: dual or single (default: dual)"
    exit 1
}

if [ $# -lt 2 ] || [ $# -gt 4 ]; then usage; fi
if [ "$(id -u)" -ne 0 ]; then echo "Error: Must run as root"; exit 1; fi

# Skip first arg (distro) for compatibility with template; remaining args are positional
KERNEL=$2
BOOT_MODE=${3:-dual}
DESKTOP_ENV=$4

if [ -z "$DESKTOP_ENV" ] || [ "$DESKTOP_ENV" = "all" ]; then
    DESKTOP_ENV="gnome"
fi

if [[ ! "$DESKTOP_ENV" =~ ^(gnome|kde|xfce)$ ]]; then
    echo "Error: desktop_environment must be gnome, kde, or xfce"
    exit 1
fi

if [[ ! "$BOOT_MODE" =~ ^(dual|single)$ ]]; then
    echo "Error: boot_mode must be dual or single"
    exit 1
fi

TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
ROOTFS_IMG="ubuntu26_${DESKTOP_ENV}_${TIMESTAMP}.img"

echo "=========================================="
echo "Starting Ubuntu 26.04 LTS RootFS Build"
echo "Desktop: $DESKTOP_ENV"
echo "Kernel: $KERNEL"
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
printf "deb %s/ %s main restricted universe multiverse\n" "$UBUNTU_MIRROR" "$UBUNTU_SUITE" > "$ROOTDIR/etc/apt/sources.list"
printf "deb %s/ %s-updates main restricted universe multiverse\n" "$UBUNTU_MIRROR" "$UBUNTU_SUITE" >> "$ROOTDIR/etc/apt/sources.list"
printf "deb %s/ %s-backports main restricted universe multiverse\n" "$UBUNTU_MIRROR" "$UBUNTU_SUITE" >> "$ROOTDIR/etc/apt/sources.list"
printf "deb %s/ %s-security main restricted universe multiverse\n" "$UBUNTU_MIRROR" "$UBUNTU_SUITE" >> "$ROOTDIR/etc/apt/sources.list"

chroot "$ROOTDIR" apt-get update

# Step 4: Base packages
chroot "$ROOTDIR" apt-get install -y --no-install-recommends \
    systemd sudo vim-tiny wget curl \
    network-manager openssh-server \
    wpasupplicant dbus kmod initramfs-tools

# Step 5: Kernel injection
if ls *.deb 1> /dev/null 2>&1; then
    cp *.deb "$ROOTDIR/tmp/"
    chroot "$ROOTDIR" bash -c "export DEBIAN_FRONTEND=noninteractive && apt-get install -y /tmp/*.deb" || {
        echo "Error: Kernel .deb installation failed, rootfs will not boot!" >&2
        exit 1
    }

    KERNEL_MODULE_DIR=$(detect_kernel_module_dir "$ROOTDIR")
    if [ -n "$KERNEL_MODULE_DIR" ]; then
        echo "Detected kernel module directory: $KERNEL_MODULE_DIR"
        chroot "$ROOTDIR" /sbin/depmod -a "$KERNEL_MODULE_DIR" || true
    fi
else
    echo "Error: No .deb kernel packages found in current directory, cannot generate bootable rootfs!" >&2
    exit 1
fi

# Step 6: Locale & hostname
chroot "$ROOTDIR" bash -c "export DEBIAN_FRONTEND=noninteractive && echo 'LANG=en_US.UTF-8' > /etc/default/locale"
chroot "$ROOTDIR" locale-gen en_US.UTF-8
echo "ubuntu26-${DESKTOP_ENV}" > "$ROOTDIR/etc/hostname"

# Step 7: Users — uses common library
setup_users "$ROOTDIR" "$ROOT_PASS" "$USER_NAME" "$USER_PASS" "sudo,audio,video,render,input,plugdev"

# Step 8: Desktop environment
if [ "$DESKTOP_ENV" = "gnome" ]; then
    chroot "$ROOTDIR" apt-get install -y --no-install-recommends ubuntu-desktop-minimal gnome-terminal firefox gdm3
elif [ "$DESKTOP_ENV" = "kde" ]; then
    chroot "$ROOTDIR" apt-get install -y --no-install-recommends plasma-desktop sddm konsole firefox plasma-workspace systemsettings discover packagekit
elif [ "$DESKTOP_ENV" = "xfce" ]; then
    chroot "$ROOTDIR" apt-get install -y --no-install-recommends xfce4 xfce4-terminal lightdm lightdm-gtk-greeter firefox mousepad thunar
fi

# Step 9: DM autologin — uses common library
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

# QRTR service — uses common library (consistent with Fedora/Arch)
setup_qrtr_service "$ROOTDIR"

# Step 11: fstab & cleanup
generate_fstab "$ROOTDIR" "$BOOT_MODE"
chroot "$ROOTDIR" apt-get clean
chroot "$ROOTDIR" rm -rf /tmp/*.deb
teardown_mounts "$ROOTDIR"

# Step 12: Pack
apply_fs_uuid "$UUID" "$ROOTFS_IMG"
echo "Raw image generated: $ROOTFS_IMG"
echo "Converting to sparse image..."
pack_sparse_image "$ROOTFS_IMG" "ubuntu26_${DESKTOP_ENV}_${TIMESTAMP}.7z"

echo "Ubuntu build successful!"
