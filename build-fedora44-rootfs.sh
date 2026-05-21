#!/bin/bash
set -e

IMAGE_SIZE="8G"
FILESYSTEM_UUID="ee8d3593-59b1-480e-a3b6-4fefb17ee7d8"
FEDORA_VERSION="44"

# 使用中科大源（已同步 Fedora 44，且网络稳定）
FEDORA_BASEURL="https://mirrors.ustc.edu.cn/fedora/linux"

usage() { echo "用法: $0 <kernel_version>"; exit 1; }
[ $# -ne 1 ] && usage
[ "$(id -u)" -ne 0 ] && { echo "请使用root权限运行"; exit 1; }

KERNEL=$1
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
ROOTFS_IMG="fedora44_${TIMESTAMP}.img"

echo "=========================================="
echo "开始构建 Fedora $FEDORA_VERSION (ARM64) RootFS"
echo "将从 kernel-bundle-$KERNEL 中提取固件并注入"
echo "=========================================="

# --- 提取固件 ---
FW_TEMP_DIR=$(mktemp -d)
FW_SOURCE_DIR=""
if [ -f firmware-xiaomi-sheng.deb ]; then
    echo "📦 从 firmware-xiaomi-sheng.deb 提取固件..."
    dpkg-deb -x firmware-xiaomi-sheng.deb "$FW_TEMP_DIR"
elif [ -f linux-xiaomi-sheng.deb ]; then
    echo "📦 从 linux-xiaomi-sheng.deb 提取固件..."
    dpkg-deb -x linux-xiaomi-sheng.deb "$FW_TEMP_DIR"
else
    echo "⚠️ 未找到包含固件的 .deb 包，将跳过固件注入"
fi

if [ -d "$FW_TEMP_DIR/lib/firmware" ]; then
    FW_SOURCE_DIR="$FW_TEMP_DIR/lib/firmware"
    echo "✅ 在 /lib/firmware 找到固件"
elif [ -d "$FW_TEMP_DIR/usr/lib/firmware" ]; then
    FW_SOURCE_DIR="$FW_TEMP_DIR/usr/lib/firmware"
    echo "✅ 在 /usr/lib/firmware 找到固件"
else
    echo "⚠️ 未找到固件目录"
fi

# --- 创建镜像 ---
rm -rf rootdir || true
truncate -s $IMAGE_SIZE "$ROOTFS_IMG"
mkfs.ext4 "$ROOTFS_IMG"
mkdir rootdir
mount -o loop "$ROOTFS_IMG" rootdir
ROOTDIR_ABS=$(realpath rootdir)

# --- 使用 dnf 安装基础系统（直接指定 baseurl，使用中科大源）---
dnf --installroot="$ROOTDIR_ABS" \
    --releasever=$FEDORA_VERSION \
    --forcearch=aarch64 \
    --nogpgcheck \
    --setopt=reposdir=/dev/null \
    --repofrompath=fedora,${FEDORA_BASEURL}/releases/$FEDORA_VERSION/Everything/aarch64/os \
    --repofrompath=fedora-updates,${FEDORA_BASEURL}/updates/$FEDORA_VERSION/Everything/aarch64/os \
    install -y \
    systemd sudo dnf kernel-core \
    NetworkManager openssh-server \
    passwd glibc-langpack-en

# --- 注入固件 ---
if [ -n "$FW_SOURCE_DIR" ]; then
    echo "📡 正在将提取的固件合并到 Fedora 系统..."
    mkdir -p "$ROOTDIR_ABS/lib/firmware"
    cp -rf "$FW_SOURCE_DIR/"* "$ROOTDIR_ABS/lib/firmware/"
    echo "✅ 固件合并完成"
fi

# --- 挂载虚拟文件系统 ---
mount --bind /dev "$ROOTDIR_ABS/dev"
mount -t proc proc "$ROOTDIR_ABS/proc"
mount -t sysfs sys "$ROOTDIR_ABS/sys"

# --- 系统配置 ---
chroot "$ROOTDIR_ABS" /bin/bash -c "echo 'LANG=en_US.UTF-8' > /etc/locale.conf"
chroot "$ROOTDIR_ABS" /bin/bash -c "echo 'fedora44' > /etc/hostname"
chroot "$ROOTDIR_ABS" bash -c "echo -e '1234\n1234' | passwd root"
chroot "$ROOTDIR_ABS" systemctl enable NetworkManager sshd

# --- 创建普通用户 ---
chroot "$ROOTDIR_ABS" useradd -m -s /bin/bash luser
chroot "$ROOTDIR_ABS" bash -c "echo 'luser:luser' | chpasswd"
chroot "$ROOTDIR_ABS" usermod -aG wheel luser

# --- 安装 GNOME 桌面（使用 dnf group install 兼容 dnf5）---
chroot "$ROOTDIR_ABS" dnf group install -y "GNOME Desktop" "GNOME Applications" "Standard"
chroot "$ROOTDIR_ABS" systemctl set-default graphical.target
chroot "$ROOTDIR_ABS" systemctl enable gdm

# --- 清理 ---
chroot "$ROOTDIR_ABS" dnf clean all
rm -rf "$ROOTDIR_ABS/var/cache/dnf"
sync; sleep 2

# --- 卸载 ---
umount "$ROOTDIR_ABS/dev" "$ROOTDIR_ABS/proc" "$ROOTDIR_ABS/sys" 2>/dev/null || true
umount rootdir 2>/dev/null || true
rm -rf rootdir
rm -rf "$FW_TEMP_DIR"

tune2fs -U $FILESYSTEM_UUID "$ROOTFS_IMG"
echo "✅ 镜像生成: $ROOTFS_IMG"
echo "🗜️ 压缩中..."
7z a "${ROOTFS_IMG}.7z" "$ROOTFS_IMG"
echo "🎉 完成！输出: ${ROOTFS_IMG}.7z"
