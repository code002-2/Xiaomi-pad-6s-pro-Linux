#!/bin/bash
set -euo pipefail

source "$(dirname "$0")/lib/rootfs-common.sh"

# --- Distro-specific configuration ---
IMAGE_SIZE="8G"
UUID="ee8d3593-59b1-480e-a3b6-4fefb17ee7d8"
UBUNTU_SUITE="resolute"
UBUNTU_MIRROR="https://mirrors.tuna.tsinghua.edu.cn/ubuntu"

# --- Password configuration ---
ROOT_PASS="${ROOT_PASS:-1234}"
USER_PASS="${USER_PASS:-luser}"
USER_NAME="${USER_NAME:-luser}"

# --- Argument parsing ---
usage() {
    echo "用法: $0 <kernel_version> <desktop_environment>"
    echo "desktop_environment: gnome, kde 或 xfce"
    exit 1
}

if [ $# -ne 2 ]; then usage; fi
if [ "$(id -u)" -ne 0 ]; then echo "请使用root权限运行"; exit 1; fi

KERNEL=$1
DESKTOP_ENV=$2

if [[ ! "$DESKTOP_ENV" =~ ^(gnome|kde|xfce)$ ]]; then
    echo "错误: desktop_environment 必须是 gnome, kde 或 xfce"
    exit 1
fi

TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
ROOTFS_IMG="ubuntu26_${DESKTOP_ENV}_${TIMESTAMP}.img"

echo "=========================================="
echo "开始构建 Ubuntu 26.04 LTS RootFS"
echo "桌面环境: $DESKTOP_ENV"
echo "内核版本: $KERNEL"
echo "=========================================="

# Step 1: Create image
create_image "$IMAGE_SIZE" "$ROOTFS_IMG" "$UUID"
setup_chroot_mounts "$ROOTDIR"

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

    KERNEL_MODULE_DIR=$(ls "$ROOTDIR/lib/modules/" | head -n 1)
    if [ -n "$KERNEL_MODULE_DIR" ]; then
        echo "动态识别到真实内核版本目录: $KERNEL_MODULE_DIR"
        chroot "$ROOTDIR" /sbin/depmod -a "$KERNEL_MODULE_DIR" || true
    fi
fi

# Step 6: Locale & hostname
chroot "$ROOTDIR" bash -c "echo 'LANG=en_US.UTF-8' > /etc/default/locale"
chroot "$ROOTDIR" locale-gen en_US.UTF-8
echo "ubuntu26-${DESKTOP_ENV}" > "$ROOTDIR/etc/hostname"

# Step 7: Users
chroot "$ROOTDIR" bash -c "echo -e '${ROOT_PASS}\n${ROOT_PASS}' | passwd root"
chroot "$ROOTDIR" useradd -m -s /bin/bash "$USER_NAME"
echo "${USER_NAME}:${USER_PASS}" | chroot "$ROOTDIR" chpasswd
chroot "$ROOTDIR" usermod -aG sudo,audio,video,render,input,plugdev "$USER_NAME"

# Step 8: Desktop environment
if [ "$DESKTOP_ENV" = "gnome" ]; then
    chroot "$ROOTDIR" apt install -y --no-install-recommends ubuntu-desktop-minimal gnome-terminal firefox gdm3
    DM="gdm3"
elif [ "$DESKTOP_ENV" = "kde" ]; then
    chroot "$ROOTDIR" apt install -y --no-install-recommends plasma-desktop sddm konsole firefox plasma-workspace systemsettings discover packagekit
    DM="sddm"
elif [ "$DESKTOP_ENV" = "xfce" ]; then
    chroot "$ROOTDIR" apt install -y --no-install-recommends xfce4 xfce4-terminal lightdm lightdm-gtk-greeter firefox mousepad thunar
    DM="lightdm"
fi

# Step 9: DM autologin config
case "$DM" in
    gdm3)
        mkdir -p "$ROOTDIR/etc/gdm3"
        printf "[daemon]\nAutomaticLoginEnable=true\nAutomaticLogin=%s\n" "$USER_NAME" > "$ROOTDIR/etc/gdm3/daemon.conf"
        chroot "$ROOTDIR" systemctl enable gdm3
        ;;
    sddm)
        mkdir -p "$ROOTDIR/etc/sddm.conf.d"
        printf "[General]\nDisplayServer=x11\nInputMethod=\n" > "$ROOTDIR/etc/sddm.conf.d/ubuntu-defaults.conf"
        printf "[Autologin]\nUser=%s\nSession=plasma\n" "$USER_NAME" > "$ROOTDIR/etc/sddm.conf.d/autologin.conf"
        if chroot "$ROOTDIR" id -u sddm >/dev/null 2>&1; then
            chroot "$ROOTDIR" usermod -aG video,render,input sddm || true
        fi
        mkdir -p "$ROOTDIR/etc/xdg"
        printf "[PowerManagement]\nScreenBlanking=false\nDisplaySleep=0\n" > "$ROOTDIR/etc/xdg/plasmarc"
        chroot "$ROOTDIR" systemctl enable sddm
        ;;
    lightdm)
        mkdir -p "$ROOTDIR/etc/lightdm/lightdm.conf.d"
        printf "[Seat:*]\nautologin-user=%s\nautologin-user-timeout=0\n" "$USER_NAME" > "$ROOTDIR/etc/lightdm/lightdm.conf.d/autologin.conf"
        chroot "$ROOTDIR" systemctl enable lightdm
        ;;
esac

chroot "$ROOTDIR" systemctl set-default graphical.target

# Step 10: Hardware quirks
chroot "$ROOTDIR" bash -c "echo 'ttyMSM0' >> /etc/securetty"
setup_getty_ttyMSM0 "$ROOTDIR"
setup_systemd_resolved_symlink "$ROOTDIR"
configure_touchscreen "$ROOTDIR"

echo "正在预配置高通 WiFi 固件修复..."
fix_wifi_firmware "$ROOTDIR"

chroot "$ROOTDIR" apt install -y qrtr-tools || true
chroot "$ROOTDIR" systemctl enable qrtr-ns || true

# Step 11: fstab & cleanup
generate_fstab "$ROOTDIR" "dual"
chroot "$ROOTDIR" apt clean
chroot "$ROOTDIR" rm -rf /tmp/*.deb
teardown_mounts "$ROOTDIR"

# Step 12: Pack
apply_fs_uuid "$UUID" "$ROOTFS_IMG"
echo "原始镜像生成完成: $ROOTFS_IMG"
echo "正在转换为 Sparse 镜像..."
pack_sparse_image "$ROOTFS_IMG" "ubuntu26_${DESKTOP_ENV}_${TIMESTAMP}.7z"

echo "🎉 Ubuntu 构建成功！"
