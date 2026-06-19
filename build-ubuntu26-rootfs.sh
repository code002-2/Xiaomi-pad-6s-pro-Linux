#!/bin/bash
set -e

IMAGE_SIZE="8G"
FILESYSTEM_UUID="ee8d3593-59b1-480e-a3b6-4fefb17ee7d8"

UBUNTU_SUITE="resolute"
UBUNTU_MIRROR="http://ports.ubuntu.com/ubuntu-ports"

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

# ========================================================
# 🔧 修复点1：先安装系统核心依赖，再安装内核！
# ========================================================
chroot rootdir apt install -y --no-install-recommends \
    systemd sudo vim-tiny wget curl \
    network-manager openssh-server \
    wpasupplicant dbus kmod initramfs-tools

if ls *.deb 1> /dev/null 2>&1; then
    cp *.deb rootdir/tmp/
    # 此时系统有了 kmod 和 initramfs-tools，内核 deb 的 post-install 脚本才能正常运行
    chroot rootdir bash -c "apt install -y /tmp/*.deb || true"
    
    # 终极保险：动态侦测真实版本并强制生成模块索引
    echo "   正在强制更新内核模块依赖..."
    KERNEL_MODULE_DIR=$(ls rootdir/lib/modules/ | head -n 1)
    if [ -n "$KERNEL_MODULE_DIR" ]; then
        echo "   ✅ 动态识别到真实内核版本目录: $KERNEL_MODULE_DIR"
        chroot rootdir /sbin/depmod -a "$KERNEL_MODULE_DIR" || true
    fi
fi

# root 用户初始化
chroot rootdir bash -c "echo -e '1234\n1234' | passwd root"
echo "sheng-ubuntu" > rootdir/etc/hostname

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

# 创建普通用户 xiaomi
chroot rootdir useradd -m -s /bin/bash xiaomi
echo "xiaomi:xiaomi" | chroot rootdir chpasswd
chroot rootdir usermod -aG sudo,audio,video,render,input,plugdev xiaomi

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
# 📶 修复点2：移植高通 8 Gen 2 WiFi 修复逻辑
# ========================================================
echo "⚙️ 正在预配置高通 WiFi 驱动适配与区域码..."
chroot rootdir apt install -y qrtr-tools || true
chroot rootdir systemctl enable qrtr-ns || true

# WiFi 区域码 (5GHz 频段支持)
echo 'options cfg80211 ieee80211_regdom=CN' > rootdir/etc/modprobe.d/cfg80211.conf

# ========================================================
# 🔒 自动登录与桌面加固配置（完全展平，杜绝任何 case 嵌套漏洞）
# ========================================================

# 1. GNOME 配置
if [ "$DM" = "gdm3" ]; then
    mkdir -p rootdir/etc/gdm3
    printf "[daemon]\nAutomaticLoginEnable=true\nAutomaticLogin=xiaomi\n" > rootdir/etc/gdm3/daemon.conf
    chroot rootdir systemctl enable gdm3
fi

# 2. KDE 降级 X11 与防息屏加固
if [ "$DM" = "sddm" ]; then
    mkdir -p rootdir/etc/sddm.conf.d
    printf "[General]\nDisplayServer=x11\nInputMethod=\n" > rootdir/etc/sddm.conf.d/ubuntu-defaults.conf
    printf "[Autologin]\nUser=xiaomi\nSession=plasma\n" > rootdir/etc/sddm.conf.d/autologin.conf
    
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
    printf "[Seat:*]\nautologin-user=xiaomi\nautologin-user-timeout=0\n" > rootdir/etc/lightdm/lightdm.conf.d/autologin.conf
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

echo "✅ 原始镜像生成完成: $ROOTFS_IMG"
# ========================================================
# ⚡ 修复点3：增加 sparse image 极速刷机转换
# ========================================================
echo "🔄 正在将其转换为 Fastboot 专用的稀疏镜像 (Sparse Image)..."
SPARSE_IMG="sparse_${ROOTFS_IMG}"
img2simg "$ROOTFS_IMG" "$SPARSE_IMG"

echo "🗜️ 正在使用 zstd 压缩..."
zstd -19 -T0 --long "$SPARSE_IMG" -o "ubuntu26_${DESKTOP_ENV}_${TIMESTAMP}.zst"

rm -f "$ROOTFS_IMG" "$SPARSE_IMG"
echo "🎉 终极修砖版 Ubuntu 构建成功！"
