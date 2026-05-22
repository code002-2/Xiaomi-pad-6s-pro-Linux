#!/bin/bash
set -e

IMAGE_SIZE="8G"
FILESYSTEM_UUID="ee8d3593-59b1-480e-a3b6-4fefb17ee7d8"

UBUNTU_SUITE="resolute"
UBUNTU_MIRROR="https://mirrors.tuna.tsinghua.edu.cn/ubuntu"

usage() {
    echo "用法: $0 <kernel_version> <desktop_environment>"
    echo "desktop_environment: gnome, kde 或 xfce"
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
DESKTOP_ENV=$2

if [[ ! "$DESKTOP_ENV" =~ ^(gnome|kde|xfce)$ ]]; then
    echo "错误: desktop_environment 必须是 gnome, kde 或 xfce"
    exit 1
fi

TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
ROOTFS_IMG="ubuntu26_${DESKTOP_ENV}_${TIMESTAMP}.img"

echo "=========================================="
echo "开始构建 Ubuntu 26.04 LTS (Resolute) RootFS"
echo "桌面环境: $DESKTOP_ENV"
echo "内核版本: $KERNEL"
echo "=========================================="

rm -rf rootdir || true
truncate -s $IMAGE_SIZE "$ROOTFS_IMG"
mkfs.ext4 "$ROOTFS_IMG"
mkdir rootdir
mount -o loop "$ROOTFS_IMG" rootdir

debootstrap --arch=arm64 "$UBUNTU_SUITE" rootdir "$UBUNTU_MIRROR"

mount --bind /dev rootdir/dev
mount --bind /dev/pts rootdir/dev/pts
mount -t proc proc rootdir/proc
mount -t sysfs sys rootdir/sys

# 基础软件源
printf "deb %s %s main restricted universe multiverse\n" "$UBUNTU_MIRROR" "$UBUNTU_SUITE" > rootdir/etc/apt/sources.list
printf "deb %s %s-updates main restricted universe multiverse\n" "$UBUNTU_MIRROR" "$UBUNTU_SUITE" >> rootdir/etc/apt/sources.list
printf "deb %s %s-backports main restricted universe multiverse\n" "$UBUNTU_MIRROR" "$UBUNTU_SUITE" >> rootdir/etc/apt/sources.list
printf "deb %s %s-security main restricted universe multiverse\n" "$UBUNTU_MIRROR" "$UBUNTU_SUITE" >> rootdir/etc/apt/sources.list

chroot rootdir apt update

if ls *.deb 1> /dev/null 2>&1; then
    cp *.deb rootdir/tmp/
    chroot rootdir bash -c "apt install -y /tmp/*.deb || true"
fi

# 基础核心依赖
chroot rootdir apt install -y --no-install-recommends \
    systemd sudo vim-tiny wget curl \
    network-manager openssh-server \
    wpasupplicant dbus

# 设置英文语言环境
chroot rootdir bash -c "echo 'LANG=en_US.UTF-8' > /etc/default/locale"
chroot rootdir locale-gen en_US.UTF-8

# root 用户初始化
chroot rootdir bash -c "echo -e '1234\n1234' | passwd root"
echo "ubuntu26-${DESKTOP_ENV}" > rootdir/etc/hostname

# ========================================================
# 📦 桌面环境分支流转 (去除一切文本写入，只留包安装)
# ========================================================
if [ "$DESKTOP_ENV" = "gnome" ]; then
    chroot rootdir apt install -y --no-install-recommends ubuntu-desktop-minimal gnome-terminal firefox gdm3
    DM="gdm3"
elif [ "$DESKTOP_ENV" = "kde" ]; then
    chroot rootdir apt install -y --no-install-recommends plasma-desktop sddm konsole firefox plasma-workspace systemsettings discover packagekit
    DM="sddm"
elif [ "$DESKTOP_ENV" = "xfce" ]; then
    chroot rootdir apt install -y --no-install-recommends xfce4 xfce4-terminal lightdm lightdm-gtk-greeter firefox mousepad thunar
    DM="lightdm"
fi

# 创建普通用户 luser
chroot rootdir useradd -m -s /bin/bash luser
echo "luser:luser" | chroot rootdir chpasswd
chroot rootdir usermod -aG sudo,audio,video,render,input,plugdev luser

# ========================================================
# ⚙️ 底层硬件自愈与触控校准
# ========================================================
chroot rootdir bash -c "echo 'ttyMSM0' >> /etc/securetty"
ln -sf /lib/systemd/system/getty@.service rootdir/etc/systemd/system/getty.target.wants/getty@ttyMSM0.service
chroot rootdir systemctl enable systemd-resolved
ln -sf /run/systemd/resolve/stub-resolv.conf rootdir/etc/resolv.conf

mkdir -p rootdir/etc/udev/rules.d/
printf 'ENV{ID_INPUT_TOUCHSCREEN}=="1", ENV{LIBINPUT_CALIBRATION_MATRIX}="1 0 0 0 1 0 0 0 1"\n' > rootdir/etc/udev/rules.d/99-touchscreen-sheng.rules

# ========================================================
# 🔒 自动登录与桌面加固配置（完全展平，杜绝任何 case 嵌套漏洞）
# ========================================================

# 1. GNOME 配置
if [ "$DM" = "gdm3" ]; then
    mkdir -p rootdir/etc/gdm3
    printf "[daemon]\nAutomaticLoginEnable=true\nAutomaticLogin=luser\n" > rootdir/etc/gdm3/daemon.conf
    chroot rootdir systemctl enable gdm3
fi

# 2. KDE 降级 X11 与防息屏加固
if [ "$DM" = "sddm" ]; then
    mkdir -p rootdir/etc/sddm.conf.d
    printf "[General]\nDisplayServer=x11\nInputMethod=\n" > rootdir/etc/sddm.conf.d/ubuntu-defaults.conf
    printf "[Autologin]\nUser=luser\nSession=plasma\n" > rootdir/etc/sddm.conf.d/autologin.conf
    
    if chroot rootdir id -u sddm >/dev/null 2>&1; then
        chroot rootdir usermod -aG video,render,input sddm || true
    fi
    
    mkdir -p rootdir/etc/xdg
    printf "[PowerManagement]\nScreenBlanking=false\nDisplaySleep=0\n" > rootdir/etc/xdg/plasmarc
    chroot rootdir systemctl enable sddm
fi

# 3. XFCE 配置
if [ "$DM" = "lightdm" ]; then
    mkdir -p rootdir/etc/lightdm/lightdm.conf.d
    printf "[Seat:*]\nautologin-user=luser\nautologin-user-timeout=0\n" > rootdir/etc/lightdm/lightdm.conf.d/autologin.conf
    chroot rootdir systemctl enable lightdm
fi

# 统一进入图形层级
chroot rootdir systemctl set-default graphical.target

# 文件系统挂载对齐
printf "PARTLABEL=linux / ext4 defaults,noatime,errors=remount-ro 0 1\n" > rootdir/etc/fstab

# 清理缓存
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
echo "🗜️ 正在生成压缩包..."
7z a "ubuntu26_${DESKTOP_ENV}_${TIMESTAMP}.7z" "$ROOTFS_IMG"
rm -f "$ROOTFS_IMG"
