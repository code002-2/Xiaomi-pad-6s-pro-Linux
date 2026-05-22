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
echo "语言环境: 英文 (en_US.UTF-8)"
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

cat > rootdir/etc/apt/sources.list <<EOF
deb $UBUNTU_MIRROR $UBUNTU_SUITE main restricted universe multiverse
deb $UBUNTU_MIRROR ${UBUNTU_SUITE}-updates main restricted universe multiverse
deb $UBUNTU_MIRROR ${UBUNTU_SUITE}-backports main restricted universe multiverse
deb $UBUNTU_MIRROR ${UBUNTU_SUITE}-security main restricted universe multiverse
EOF

chroot rootdir apt update

if ls *.deb 1> /dev/null 2>&1; then
    cp *.deb rootdir/tmp/
    chroot rootdir bash -c "apt install -y /tmp/*.deb || true"
fi

# 基础包
chroot rootdir apt install -y --no-install-recommends \
    systemd sudo vim-tiny wget curl \
    network-manager openssh-server \
    wpasupplicant dbus

# 设置英文 locale
chroot rootdir bash -c "echo 'LANG=en_US.UTF-8' > /etc/default/locale"
chroot rootdir locale-gen en_US.UTF-8

# root 密码
chroot rootdir bash -c "echo -e '1234\n1234' | passwd root"
echo "ubuntu26-${DESKTOP_ENV}" > rootdir/etc/hostname

# =========================
# 桌面环境安装
# =========================
case "$DESKTOP_ENV" in
    gnome)
        chroot rootdir apt install -y --no-install-recommends \
            ubuntu-desktop-minimal \
            gnome-terminal \
            firefox \
            gdm3
        DM="gdm3"
        ;;
    kde)
        chroot rootdir apt install -y --no-install-recommends \
            plasma-desktop \
            sddm \
            konsole \
            firefox \
            plasma-workspace \
            systemsettings \
            discover \
            packagekit
        DM="sddm"
        ;;
    xfce)
        chroot rootdir apt install -y --no-install-recommends \
            xfce4 \
            xfce4-terminal \
            lightdm \
            lightdm-gtk-greeter \
            firefox \
            mousepad \
            thunar
        DM="lightdm"
        ;;
esac

# 创建普通用户并注入完整的硬件组权限
chroot rootdir useradd -m -s /bin/bash luser
echo "luser:luser" | chroot rootdir chpasswd
chroot rootdir usermod -aG sudo,audio,video,render,input,plugdev luser

# ========================================================
# ⚙️ 注入高通特定平台优化
# ========================================================
chroot rootdir bash -c "echo 'ttyMSM0' >> /etc/securetty"
ln -sf /lib/systemd/system/getty@.service rootdir/etc/systemd/system/getty.target.wants/getty@ttyMSM0.service
chroot rootdir systemctl enable systemd-resolved
ln -sf /run/systemd/resolve/stub-resolv.conf rootdir/etc/resolv.conf

# 自动挂触控翻转校准矩阵
mkdir -p rootdir/etc/udev/rules.d/
cat > rootdir/etc/udev/rules.d/99-touchscreen-sheng.rules <<EOF
ENV{ID_INPUT_TOUCHSCREEN}=="1", ENV{LIBINPUT_CALIBRATION_MATRIX}="1 0 0 0 1 0 0 0 1"
EOF
# ========================================================

# 自动登录配置
case "$DM" in
    gdm3)
        mkdir -p rootdir/etc/gdm3
        cat > rootdir/etc/gdm3/daemon.conf <<EOF
[daemon]
AutomaticLoginEnable=true
AutomaticLogin=luser
EOF
        chroot rootdir systemctl enable gdm3
        ;;
    sddm)
        mkdir -p rootdir/etc/sddm.conf.d
        cat > rootdir/etc/sddm.conf.d/autologin.conf <<EOF
[Autologin]
User=luser
Session=plasma
EOF
        chroot rootdir systemctl enable sddm
        ;;
    lightdm)
        mkdir -p rootdir/etc/lightdm/lightdm.conf.d
        cat > rootdir/etc/lightdm/lightdm.conf.d/autologin.conf <<EOF
[Seat:*]
autologin-user=luser
autologin-user-timeout=0
EOF
        chroot rootdir systemctl enable lightdm
        ;;
esac

chroot rootdir systemctl set-default graphical.target

# fstab 对齐
cat > rootdir/etc/fstab <<EOF
PARTLABEL=linux / ext4 defaults,noatime,errors=remount-ro 0 1
EOF

chroot rootdir apt clean
chroot rootdir rm -rf /tmp/*.deb

umount rootdir/dev/pts || true
umount rootdir/dev || true
umount rootdir/proc || true
umount rootdir/sys || true
umount rootdir || true
rm -rf rootdir

tune2fs -U $FILESYSTEM_UUID "$ROOTFS_IMG"

echo "✅ 镜像生成: $ROOTFS_IMG"
echo "🗜️ 压缩中..."
7z a "${ROOTFS_IMG}.7z" "$ROOTFS_IMG"
echo "🎉 完成！输出文件: ${ROOTIMG}.7z"
