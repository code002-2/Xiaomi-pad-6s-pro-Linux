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
echo "⏳ 开始构建纯净桌面版 Debian 13 (Trixie) RootFS"
echo "内核版本: $KERNEL"
echo "=========================================="

rm -rf rootdir || true
truncate -s $IMAGE_SIZE "$ROOTFS_IMG"
mkfs.ext4 "$ROOTFS_IMG"
mkdir rootdir
mount -o loop "$ROOTFS_IMG" rootdir

# 基础系统自举安装
debootstrap --arch=arm64 "$DEBIAN_SUITE" rootdir "$DEBIAN_MIRROR"

mount --bind /dev rootdir/dev
mount --bind /dev/pts rootdir/dev/pts
mount -t proc proc rootdir/proc
mount -t sysfs sys rootdir/sys

# 严格配置 Debian 官方国内镜像源（无残留）
printf "deb %s %s main contrib non-free non-free-firmware\n" "$DEBIAN_MIRROR" "$DEBIAN_SUITE" > rootdir/etc/apt/sources.list
printf "deb %s %s-updates main contrib non-free non-free-firmware\n" "$DEBIAN_MIRROR" "$DEBIAN_SUITE" >> rootdir/etc/apt/sources.list
printf "deb %s %s-proposed-updates main contrib non-free non-free-firmware\n" "$DEBIAN_MIRROR" "$DEBIAN_SUITE" >> rootdir/etc/apt/sources.list
chroot rootdir apt update

if ls *.deb 1> /dev/null 2>&1; then
    cp *.deb rootdir/tmp/
    chroot rootdir bash -c "apt install -y /tmp/*.deb || true"
fi

# 🚨 精简修改：移除了带有 Server 标记的 openssh-server 构建依赖，仅保留桌面终端必需的底层连接件
chroot rootdir apt install -y --no-install-recommends \
    systemd systemd-resolved sudo vim-tiny wget curl network-manager wpasupplicant dbus locales

# 🌐 语言环境初始化 (🚨 修复：将路径完美纠正为 Debian 官方的 /etc/locale.gen)
chroot rootdir bash -c "echo 'LANG=en_US.UTF-8' > /etc/default/locale"
chroot rootdir sed -i 's/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
chroot rootdir locale-gen en_US.UTF-8

# 密码设置
chroot rootdir bash -c "echo -e '1234\n1234' | passwd root"

# 主机名完全调整为 debian-sheng
echo "debian-sheng" > rootdir/etc/hostname

# 仅通过 task-gnome-desktop 编译 Debian 标准图形层
chroot rootdir apt install -y --no-install-recommends task-gnome-desktop gdm3

# 创建普通用户并分配合规的硬件访问权限组
chroot rootdir useradd -m -s /bin/bash luser
echo "luser:luser" | chroot rootdir chpasswd
chroot rootdir usermod -aG sudo,audio,video,render,input luser

echo "🩹 正在针对高通 SM8550 (Sheng) 注入底层自愈补丁..."
chroot rootdir bash -c "echo 'ttyMSM0' >> /etc/securetty"
ln -sf /lib/systemd/system/getty@.service rootdir/etc/systemd/system/getty.target.wants/getty@ttyMSM0.service

# 激活 DNS 托管解析
chroot rootdir systemctl enable systemd-resolved
ln -sf /run/systemd/resolve/stub-resolv.conf rootdir/etc/resolv.conf

# 触控屏幕方向与矩阵校准规则
mkdir -p rootdir/etc/udev/rules.d/
printf 'ENV{ID_INPUT_TOUCHSCREEN}=="1", ENV{LIBINPUT_CALIBRATION_MATRIX}="1 0 0 0 1 0 0 0 1"\n' > rootdir/etc/udev/rules.d/99-touchscreen-sheng.rules

# GDM3 自动登录配置。改用纯净的常规配置写法
mkdir -p rootdir/etc/gdm3
printf "[daemon]\nAutomaticLoginEnable=true\nAutomaticLogin=luser\n" > rootdir/etc/gdm3/daemon.conf
chroot rootdir systemctl enable gdm3

# 强制进入图形化靶位
chroot rootdir systemctl set-default graphical.target

# 文件系统挂载对齐
printf "PARTLABEL=linux / ext4 defaults,noatime,errors=remount-ro 0 1\n" > rootdir/etc/fstab

# 清理构建缓存
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

echo "🎉 精简桌面版 Debian 13 自动化编译全部圆满成功！"
