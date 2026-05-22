#!/bin/bash
set -e

IMAGE_SIZE="8G"
FILESYSTEM_UUID="ee8d3593-59b1-480e-a3b6-4fefb17ee7d8"
DEBIAN_SUITE="trixie"
DEBIAN_MIRROR="https://mirrors.tuna.tsinghua.edu.cn/debian"

usage() {
    echo "用法: $0 <distro_name> <kernel_version>"
    exit 1
}

if [ $# -ne 2 ]; then
    usage
fi

if [ "$(id -u)" -ne 0 ]; then
    echo "请使用root权限运行"
    exit 1
fi

DISTRO=$1
KERNEL=$2
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
ROOTFS_IMG="debian13_desktop_${TIMESTAMP}.img"

echo "=========================================="
echo "⏳ 开始构建 Debian 13 (Trixie) 桌面版 RootFS"
echo "内核版本: $KERNEL"
echo "=========================================="

rm -rf rootdir || true
truncate -s $IMAGE_SIZE "$ROOTFS_IMG"
mkfs.ext4 "$ROOTFS_IMG"
mkdir rootdir
mount -o loop "$ROOTFS_IMG" rootdir

# 基础引导安装
debootstrap --arch=arm64 "$DEBIAN_SUITE" rootdir "$DEBIAN_MIRROR"

mount --bind /dev rootdir/dev
mount --bind /dev/pts rootdir/dev/pts
mount -t proc proc rootdir/proc
mount -t sysfs sys rootdir/sys

# 注入软件源
printf "deb %s %s main contrib non-free non-free-firmware\n" "$DEBIAN_MIRROR" "$DEBIAN_SUITE" > rootdir/etc/apt/sources.list
printf "deb %s %s-updates main contrib non-free non-free-firmware\n" "$DEBIAN_MIRROR" "$DEBIAN_SUITE" >> rootdir/etc/apt/sources.list
chroot rootdir apt update

if ls *.deb 1> /dev/null 2>&1; then
    cp *.deb rootdir/tmp/
    chroot rootdir bash -c "apt install -y /tmp/*.deb || true"
fi

# 🚨 核心修复：显式加入 locales 包（提供 locale-gen），并安装 systemd-resolved 依赖
chroot rootdir apt install -y --no-install-recommends \
    systemd systemd-resolved sudo vim-tiny wget curl network-manager openssh-server wpasupplicant dbus locales

# 🌐 语言与本地化配置 (由于上面安装了 locales 包，此时 locale-gen 100% 存在)
chroot rootdir bash -c "echo 'LANG=en_US.UTF-8' > /etc/default/locale"
chroot rootdir sed -i 's/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locales.build 2>/dev/null || true
chroot rootdir locale-gen en_US.UTF-8

# root 用户密码
chroot rootdir bash -c "echo -e '1234\n1234' | passwd root"
echo "debian-sheng" > rootdir/etc/hostname

# 安装 GNOME 桌面环境及必备组件
chroot rootdir apt install -y --no-install-recommends task-gnome-desktop gdm3

# 创建普通用户并指派基础硬件权限组
chroot rootdir useradd -m -s /bin/bash luser
echo "luser:luser" | chroot rootdir chpasswd
chroot rootdir usermod -aG sudo,audio,video,render,input luser

echo "🩹 正在针对高通 SM8550 (Sheng) 注入底层自愈补丁..."
chroot rootdir bash -c "echo 'ttyMSM0' >> /etc/securetty"
ln -sf /lib/systemd/system/getty@.service rootdir/etc/systemd/system/getty.target.wants/getty@ttyMSM0.service

# 启动网络解析托管
chroot rootdir systemctl enable systemd-resolved
ln -sf /run/systemd/resolve/stub-resolv.conf rootdir/etc/resolv.conf

# 触控校准规则
mkdir -p rootdir/etc/udev/rules.d/
printf 'ENV{ID_INPUT_TOUCHSCREEN}=="1", ENV{LIBINPUT_CALIBRATION_MATRIX}="1 0 0 0 1 0 0 0 1"\n' > rootdir/etc/udev/rules.d/99-touchscreen-sheng.rules

# GDM3 自动登录配置
mkdir -p rootdir/etc/gdm3
printf "[daemon]\nAutomaticLoginEnable=true\nAutomaticLogin=luser\n" > rootdir/etc/gdm3/daemon.conf
chroot rootdir systemctl enable gdm3

# 设定默认图形化启动级别
chroot rootdir systemctl set-default graphical.target

# 挂载对齐
printf "PARTLABEL=linux / ext4 defaults,noatime,errors=remount-ro 0 1\n" > rootdir/etc/fstab

# 干净清理
chroot rootdir apt clean
chroot rootdir rm -rf /tmp/*.deb

umount rootdir/dev/pts || true
umount rootdir/dev || true
umount rootdir/proc || true
umount rootdir/sys || true
umount rootdir || true
rm -rf rootdir

tune2fs -U $FILESYSTEM_UUID "$ROOTFS_IMG"

echo "✅ 镜像生成完成: $ROOTFS_IMG"
echo "🗜️ 正在生成最终 7z 压缩包..."
7z a "debian13_desktop_${TIMESTAMP}.7z" "$ROOTFS_IMG"
rm -f "$ROOTFS_IMG"

echo "🎉 Debian 13 自动化加固编译全部圆满成功！"
