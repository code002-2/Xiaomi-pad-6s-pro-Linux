#!/bin/bash
set -e

# 🛡️ 异常守护：确保挂载点自动清理
cleanup() {
    umount -l rootdir/dev/pts 2>/dev/null || true
    umount -l rootdir/dev 2>/dev/null || true
    umount -l rootdir/proc 2>/dev/null || true
    umount -l rootdir/sys 2>/dev/null || true
    umount -l rootdir 2>/dev/null || true
}
trap cleanup EXIT ERR

IMAGE_SIZE="8G"
UBUNTU_SUITE="resolute"
BUILD_MIRROR="http://archive.ubuntu.com/ubuntu"
TARGET_MIRROR="https://mirrors.tuna.tsinghua.edu.cn/ubuntu"

if [ $# -ne 2 ]; then
    echo "用法: $0 <kernel_version> <desktop_environment>"
    exit 1
fi

KERNEL=$1
DESKTOP_ENV=$2

# 初始化镜像
truncate -s $IMAGE_SIZE "ubuntu26.img"
mkfs.ext4 "ubuntu26.img"
mkdir -p rootdir
mount -o loop "ubuntu26.img" rootdir

# 基础引导
debootstrap --arch=arm64 "$UBUNTU_SUITE" rootdir "$BUILD_MIRROR"

# 挂载必要的虚拟文件系统
mount --bind /dev rootdir/dev
mount --bind /dev/pts rootdir/dev/pts
mount -t proc proc rootdir/proc
mount -t sysfs sys rootdir/sys

# 配置 APT 源
printf "deb %s %s main restricted universe multiverse\n" "$BUILD_MIRROR" "$UBUNTU_SUITE" > rootdir/etc/apt/sources.list

export DEBIAN_FRONTEND=noninteractive

# 安装加速工具
chroot rootdir apt-get update
chroot rootdir apt-get install -y eatmydata

# 安装核心组件 (包含平板触控优化)
chroot rootdir eatmydata apt-get install -y --no-install-recommends \
    systemd sudo vim network-manager openssh-server \
    gnome-tweaks gnome-shell-extension-manager \
    xdg-desktop-portal-gnome maliit-keyboard \
    parted e2fsprogs

# 根据桌面环境安装
if [ "$DESKTOP_ENV" = "gnome" ]; then
    chroot rootdir eatmydata apt-get install -y --no-install-recommends ubuntu-desktop-minimal gdm3
fi

# 注入触控校准
mkdir -p rootdir/etc/udev/rules.d/
echo 'ENV{ID_INPUT_TOUCHSCREEN}=="1", ENV{LIBINPUT_CALIBRATION_MATRIX}="1 0 0 0 1 0 0 0 1"' > rootdir/etc/udev/rules.d/99-touchscreen-sheng.rules

# 自动扩容与最终源替换
printf "PARTLABEL=linux / ext4 defaults,noatime,errors=remount-ro,x-systemd.growfs 0 1\n" > rootdir/etc/fstab
printf "deb %s %s main restricted universe multiverse\n" "$TARGET_MIRROR" "$UBUNTU_SUITE" > rootdir/etc/apt/sources.list

# 清理与打包
chroot rootdir apt-get clean
cleanup
7z a -t7z -m0=lzma2 -mx=5 -mmt=on "ubuntu26_${DESKTOP_ENV}.7z" "ubuntu26.img"
echo "✅ 构建完成！"
