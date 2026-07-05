#!/bin/bash
set -euo pipefail

source "$(dirname "$0")/lib/rootfs-common.sh"

# --- Distro-specific configuration ---
IMAGE_SIZE="8G"
UUID="ee8d3593-59b1-480e-a3b6-4fefb17ee7d8"

# --- Password configuration ---
ROOT_PASS="${ROOT_PASS:-1234}"
USER_PASS="${USER_PASS:-luser}"
USER_NAME="${USER_NAME:-luser}"

# --- Argument parsing ---
if [ $# -ne 3 ]; then
    echo "用法: $0 <distro_name> <kernel_version> <desktop_env>"
    echo "desktop_env 必须是 'gnome' 或 'kde'"
    exit 1
fi
if [ "$(id -u)" -ne 0 ]; then echo "请使用root权限运行"; exit 1; fi

DISTRO=$1
KERNEL=$2
DESKTOP=$3
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
ROOTFS_IMG="kali_${DESKTOP}_desktop_${TIMESTAMP}.img"

echo "=========================================="
echo "开始构建渗透测试版 Kali Linux ARM RootFS"
echo "内核版本: $KERNEL | 桌面环境: ${DESKTOP^^}"
echo "=========================================="

# Step 1: Create image
create_image "$IMAGE_SIZE" "$ROOTFS_IMG" "$UUID"

# Step 2: Docker extraction
echo "正在通过 Docker 提取 Kali Linux 官方 arm64 滚动版底包..."
docker pull --platform linux/arm64 kalilinux/kali-rolling:latest
docker create --name kali-temp kalilinux/kali-rolling:latest
docker export kali-temp | tar -x -C "$ROOTDIR/"
docker rm kali-temp

setup_chroot_mounts "$ROOTDIR"
setup_dns "$ROOTDIR" 8.8.8.8 1.1.1.1

# Step 3: Desktop environment & base packages
export DEBIAN_FRONTEND=noninteractive
echo "正在更新 Kali 系统并安装核心组件与 ${DESKTOP^^} 桌面..."

if [ "$DESKTOP" = "gnome" ]; then
    chroot "$ROOTDIR" apt-get install -y --no-install-recommends \
        kali-linux-core kali-desktop-gnome gdm3 \
        systemd systemd-sysv udev sudo vim wget curl tar xz-utils pciutils findutils \
        network-manager wpasupplicant dialog kmod qrtr-tools ca-certificates init
elif [ "$DESKTOP" = "kde" ]; then
    chroot "$ROOTDIR" apt-get install -y --no-install-recommends \
        kali-linux-core kali-desktop-kde sddm \
        systemd systemd-sysv udev sudo vim wget curl tar xz-utils pciutils findutils \
        network-manager wpasupplicant dialog kmod qrtr-tools ca-certificates init
else
    echo "错误的桌面环境参数: $DESKTOP"
    exit 1
fi

# Step 4: Kernel injection
echo "正在扫描并注入本地内核与系统固件包..."
if ls *.deb 1> /dev/null 2>&1; then
    for pkg in *.deb; do
        dpkg-deb --fsys-tarfile "$pkg" | tar -x --keep-directory-symlink -C "$ROOTDIR/"
    done
    KERNEL_MODULE_DIR=$(ls "$ROOTDIR/lib/modules/" | head -n 1)
    if [ -n "$KERNEL_MODULE_DIR" ]; then
        chroot "$ROOTDIR" /sbin/depmod -a "$KERNEL_MODULE_DIR" || true
    fi
fi

if ls *.tar.gz 1> /dev/null 2>&1; then
    for tarball in *.tar.gz; do
        tar -xz --keep-directory-symlink -f "$tarball" -C "$ROOTDIR/"
    done
fi

# Step 5: Users & hostname
chroot "$ROOTDIR" bash -c "echo 'root:${ROOT_PASS}' | chpasswd"
echo "kali-sheng" > "$ROOTDIR/etc/hostname"
chroot "$ROOTDIR" useradd -m -s /bin/bash "$USER_NAME"
chroot "$ROOTDIR" bash -c "echo '${USER_NAME}:${USER_PASS}' | chpasswd"
chroot "$ROOTDIR" usermod -aG sudo,audio,video,input,netdev "$USER_NAME"
echo "%sudo ALL=(ALL:ALL) NOPASSWD: ALL" > "$ROOTDIR/etc/sudoers.d/sudo-nopasswd"
chmod 440 "$ROOTDIR/etc/sudoers.d/sudo-nopasswd"

# Step 6: SELinux & service masking
echo "彻底禁用 SELinux (骗过高通内核)..."
mkdir -p "$ROOTDIR/etc/selinux"
echo "SELINUX=disabled" > "$ROOTDIR/etc/selinux/config"
echo "SELINUXTYPE=targeted" >> "$ROOTDIR/etc/selinux/config"

echo "拉黑 ModemManager 和 fwupd (防止扫描导致高通固件崩溃重启)..."
chroot "$ROOTDIR" systemctl mask ModemManager.service || true
chroot "$ROOTDIR" systemctl mask fwupd.service || true
chroot "$ROOTDIR" systemctl mask systemd-networkd-wait-online.service || true

# Step 7: Hardware quirks
echo "注入底层自愈补丁..."
setup_getty_ttyMSM0 "$ROOTDIR"
chroot "$ROOTDIR" systemctl enable NetworkManager
configure_touchscreen "$ROOTDIR"

# Autologin
if [ "$DESKTOP" = "gnome" ]; then
    echo "配置 GDM3 (GNOME) 自动登录..."
    chroot "$ROOTDIR" systemctl enable gdm3
    chroot "$ROOTDIR" systemctl set-default graphical.target
    mkdir -p "$ROOTDIR/etc/gdm3"
    printf "[daemon]\nAutomaticLoginEnable=True\nAutomaticLogin=%s\n" "$USER_NAME" > "$ROOTDIR/etc/gdm3/daemon.conf"
elif [ "$DESKTOP" = "kde" ]; then
    echo "配置 SDDM (KDE) 自动登录..."
    chroot "$ROOTDIR" systemctl enable sddm
    chroot "$ROOTDIR" systemctl set-default graphical.target
    mkdir -p "$ROOTDIR/etc/sddm.conf.d"
    printf "[Autologin]\nUser=%s\nSession=plasma\n" "$USER_NAME" > "$ROOTDIR/etc/sddm.conf.d/autologin.conf"
fi

# WiFi fix
echo "正在预配置高通 WiFi 固件修复..."
FW_DIR="$ROOTDIR/lib/firmware/ath12k/WCN7850/hw2.0"
if [ -f "$FW_DIR/board-2.bin" ]; then
    cp "$FW_DIR/board-2.bin" "$FW_DIR/board.bin"
fi

# Module rename
MOD_DIR="$ROOTDIR/lib/modules"
TARGET_VER="7.0.0-sm8550-gf273227fab85"
if [ -d "$MOD_DIR" ]; then
    for dir in "$MOD_DIR"/*; do
        if [ -d "$dir" ] && [ "$(basename "$dir")" != "$TARGET_VER" ]; then
            mv "$dir" "$MOD_DIR/$TARGET_VER"
            chroot "$ROOTDIR" /sbin/depmod -a "$TARGET_VER" || true
            break
        fi
    done
fi

# QRTR service
cat <<'EOF' > "$ROOTDIR/etc/systemd/system/qrtr-force.service"
[Unit]
Description=Qualcomm IPC Router Service (QRTR)
After=network.target

[Service]
ExecStart=/usr/bin/qrtr-ns -f
Restart=always

[Install]
WantedBy=multi-user.target
EOF
chroot "$ROOTDIR" systemctl enable qrtr-force.service

# Step 8: fstab & cleanup
generate_fstab "$ROOTDIR" "dual"
chroot "$ROOTDIR" apt-get clean
teardown_mounts "$ROOTDIR"

# Step 9: Pack
apply_fs_uuid "$UUID" "$ROOTFS_IMG"
pack_sparse_image "$ROOTFS_IMG" "kali_${DESKTOP}_desktop_${TIMESTAMP}.7z"

echo "🎉 Kali Linux ARM (${DESKTOP^^} 版本) 构建圆满成功！"
