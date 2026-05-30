#!/bin/bash
set -e

IMAGE_SIZE="8G"
FILESYSTEM_UUID="ee8d3593-59b1-480e-a3b6-4fefb17ee7d8"

usage() {
    echo "用法: $0 <kernel_version> <iso_file>"
    exit 1
}

if [ $# -ne 2 ]; then
    usage
fi

if [ "$(id -u)" -ne 0 ]; then
    echo "请使用root权限运行"
    exit 1
fi

KERNEL=$1
ISO_FILE=$2
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
ROOTFS_IMG="gxdeos_iso_desktop_${TIMESTAMP}.img"

echo "=========================================="
echo "⏳ 开始构建 GXDE OS ARM (基于官方 ISO 解包版)"
echo "内核版本: $KERNEL"
echo "使用镜像: $ISO_FILE"
echo "=========================================="

rm -rf rootdir || true
truncate -s $IMAGE_SIZE "$ROOTFS_IMG"
mkfs.ext4 "$ROOTFS_IMG"
mkdir rootdir
mount -o loop "$ROOTFS_IMG" rootdir

echo "⬇️ 正在挂载 ISO 镜像并提取只读系统核心 (Squashfs)..."
mkdir -p /tmp/iso_mount
mount -o loop "$ISO_FILE" /tmp/iso_mount

# 查找 Debian/Deepin 体系常见的 live 根文件系统压缩包
SQUASHFS=""
if [ -f /tmp/iso_mount/live/filesystem.squashfs ]; then
    SQUASHFS="/tmp/iso_mount/live/filesystem.squashfs"
elif [ -f /tmp/iso_mount/casper/filesystem.squashfs ]; then
    SQUASHFS="/tmp/iso_mount/casper/filesystem.squashfs"
fi

if [ -z "$SQUASHFS" ]; then
    echo "❌ 无法在 ISO 中找到 filesystem.squashfs！请检查 ISO 格式。"
    umount /tmp/iso_mount
    exit 1
fi

echo "📦 正在将官方系统释放到我们的磁盘中 (这可能需要几分钟)..."
unsquashfs -f -d rootdir "$SQUASHFS"
umount /tmp/iso_mount

echo "🔌 挂载虚拟文件系统..."
mount --bind /dev rootdir/dev
mount --bind /dev/pts rootdir/dev/pts
mount -t proc proc rootdir/proc
mount -t sysfs sys rootdir/sys

# 移除 Live CD 可能残留的安装向导 (如果有)
rm -f rootdir/etc/resolv.conf
echo "nameserver 8.8.8.8" > rootdir/etc/resolv.conf
echo "nameserver 1.1.1.1" >> rootdir/etc/resolv.conf

export DEBIAN_FRONTEND=noninteractive

echo "📦 正在补充底层缺失工具 (桌面环境已由 ISO 自带)..."
# 我们只需补充极其关键的高通通讯工具，桌面不用装了！
chroot rootdir apt-get update
chroot rootdir apt-get install -y --no-install-recommends \
    network-manager wpasupplicant kmod qrtr-tools

echo "🔨 正在扫描并注入本地内核与系统固件包..."
if ls *.deb 1> /dev/null 2>&1; then
    for pkg in *.deb; do
        dpkg-deb --fsys-tarfile "$pkg" | tar -x --keep-directory-symlink -C rootdir/
    done
    KERNEL_MODULE_DIR=$(ls rootdir/lib/modules/ | head -n 1)
    if [ -n "$KERNEL_MODULE_DIR" ]; then
        chroot rootdir /sbin/depmod -a "$KERNEL_MODULE_DIR" || true
    fi
fi

if ls *.tar.gz 1> /dev/null 2>&1; then
    for tarball in *.tar.gz; do
        tar -xz --keep-directory-symlink -f "$tarball" -C rootdir/
    done
fi

# 重置 root 密码，创建默认用户
chroot rootdir bash -c "echo 'root:1234' | chpasswd"
echo "gxdeos-sheng" > rootdir/etc/hostname

# 检查 luser 是否已存在 (有些 Live CD 默认自带特定用户)
if ! chroot rootdir id -u luser >/dev/null 2>&1; then
    chroot rootdir useradd -m -s /bin/bash luser
fi
chroot rootdir bash -c "echo 'luser:luser' | chpasswd"
chroot rootdir usermod -aG sudo,audio,video,input,netdev luser
echo "%sudo ALL=(ALL:ALL) NOPASSWD: ALL" > rootdir/etc/sudoers.d/sudo-nopasswd
chmod 440 rootdir/etc/sudoers.d/sudo-nopasswd

# ==========================================
# 🚨 核心防死机护甲 (骗过高通看门狗)
# ==========================================
echo "🩹 彻底禁用 SELinux (骗过高通内核)..."
mkdir -p rootdir/etc/selinux
echo "SELINUX=disabled" > rootdir/etc/selinux/config
echo "SELINUXTYPE=targeted" >> rootdir/etc/selinux/config

echo "🩹 彻底拉黑 ModemManager 和 fwupd (防止扫描导致高通固件崩溃)..."
chroot rootdir systemctl mask ModemManager.service || true
chroot rootdir systemctl mask fwupd.service || true
chroot rootdir systemctl mask systemd-networkd-wait-online.service || true
# ==========================================

echo "🩹 注入底层自愈补丁..."
ln -sf /lib/systemd/system/getty@.service rootdir/etc/systemd/system/getty.target.wants/getty@ttyMSM0.service
chroot rootdir systemctl enable NetworkManager

mkdir -p rootdir/etc/udev/rules.d/
printf 'ENV{ID_INPUT_TOUCHSCREEN}=="1", ENV{LIBINPUT_CALIBRATION_MATRIX}="1 0 0 0 1 0 0 0 1"\n' > rootdir/etc/udev/rules.d/99-touchscreen-sheng.rules

echo "⚙️ 正在预配置高通 WiFi 固件修复与驱动适配..."
FW_DIR="rootdir/lib/firmware/ath12k/WCN7850/hw2.0"
if [ -f "$FW_DIR/board-2.bin" ]; then
    cp "$FW_DIR/board-2.bin" "$FW_DIR/board.bin"
fi

MOD_DIR="rootdir/lib/modules"
TARGET_VER="7.0.0-sm8550-gf273227fab85"
if [ -d "$MOD_DIR" ]; then
    for dir in "$MOD_DIR"/*; do
        if [ -d "$dir" ] && [ "$(basename "$dir")" != "$TARGET_VER" ]; then
            mv "$dir" "$MOD_DIR/$TARGET_VER"
            chroot rootdir /sbin/depmod -a "$TARGET_VER" || true
            break
        fi
    done
fi

cat << 'EOF' > rootdir/etc/systemd/system/qrtr-force.service
[Unit]
Description=Qualcomm IPC Router Service (QRTR)
After=network.target

[Service]
ExecStart=/usr/bin/qrtr-ns -f
Restart=always

[Install]
WantedBy=multi-user.target
EOF

chroot rootdir systemctl enable qrtr-force.service
printf "PARTLABEL=linux / ext4 defaults,noatime,errors=remount-ro 0 1\n" > rootdir/etc/fstab
chroot rootdir apt-get clean

echo "🧹 正在清理后台遗留进程并安全卸载..."
fuser -k -9 -m rootdir || true
sleep 2

umount -l rootdir/dev/pts || true
umount -l rootdir/dev || true
umount -l rootdir/proc || true
umount -l rootdir/sys || true
umount -l rootdir || true
sleep 2
rm -rf rootdir

tune2fs -U $FILESYSTEM_UUID "$ROOTFS_IMG"
SPARSE_IMG="sparse_${ROOTFS_IMG}"
img2simg "$ROOTFS_IMG" "$SPARSE_IMG"
7z a "gxdeos_iso_desktop_${TIMESTAMP}.7z" "$SPARSE_IMG"
rm -f "$ROOTFS_IMG" "$SPARSE_IMG"

echo "🎉 GXDE OS (ISO 提取版) 构建圆满成功！"
