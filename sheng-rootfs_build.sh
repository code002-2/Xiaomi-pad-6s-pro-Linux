#!/bin/bash
set -e

IMAGE_SIZE="8G"
FILESYSTEM_UUID="ee8d3593-59b1-480e-a3b6-4fefb17ee7d8"

if [ $# -lt 2 ]; then
    echo "Usage: $0 <distro-variant> <kernel>"
    exit 1
fi

if [ "$(id -u)" -ne 0 ]; then
    echo "Run as root"
    exit 1
fi

DISTRO=$1
KERNEL=$2

distro_type=$(echo "$DISTRO" | cut -d'-' -f1)
distro_variant=$(echo "$DISTRO" | cut -d'-' -f2)

if [ "$distro_type" != "debian" ]; then
    echo "Only debian supported"
    exit 1
fi

distro_version="trixie"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

# 🔥 MULTI FLAVOUR
FLAVOURS=("gnome")
BOOTMODES=("dual")

for FLAVOUR in "${FLAVOURS[@]}"; do
for MODE in "${BOOTMODES[@]}"; do

echo ""
echo "======================================"
echo "🚀 BUILD: $FLAVOUR - $MODE"
echo "======================================"

ROOTFS_IMG="${distro_type}_${distro_version}_${FLAVOUR}_${MODE}_${TIMESTAMP}.img"

rm -rf rootdir || true

truncate -s $IMAGE_SIZE "$ROOTFS_IMG"
mkfs.ext4 "$ROOTFS_IMG"

mkdir rootdir
mount -o loop "$ROOTFS_IMG" rootdir

# bootstrap
debootstrap --arch=arm64 "$distro_version" rootdir http://deb.debian.org/debian/

# mount
mount --bind /dev rootdir/dev
mount --bind /dev/pts rootdir/dev/pts
mount -t proc proc rootdir/proc
mount -t sysfs sys rootdir/sys

# base packages
chroot rootdir apt update
chroot rootdir apt install -y \
    systemd sudo vim wget curl \
    network-manager openssh-server \
    wpasupplicant dbus

echo "📦 Installing device-specific .deb packages..."

# Copy semua .deb ke rootfs
cp *.deb rootdir/tmp/

# Install dependency dulu (biar aman)
chroot rootdir apt install -y \
    libglib2.0-0 \
    libprotobuf-c1 \
    libqmi-glib5 \
    libmbim-glib4 || true

# Install satu per satu (biar gampang debug kalau gagal)
ls -lah rootdir/tmp/

chroot rootdir bash -c "apt update && apt install -y /tmp/*.deb" || exit 1

echo "✅ All custom .deb installed"

# ========================================================
# ⚙️ 注入高通移动端自愈配置与平板专属修补
# ========================================================
echo "🩹 正在针对高通 SM8550 (Sheng) 注入底层自愈补丁..."

# 1. 锁死主线串口控制台守候进程 (本级防御：开机黑屏时保留串口救砖通道)
chroot rootdir bash -c "echo 'ttyMSM0' >> /etc/securetty"
ln -sf /lib/systemd/system/getty@.service rootdir/etc/systemd/system/getty.target.wants/getty@ttyMSM0.service

# 2. 修复 DNS 无法解析导致联网后无法刷网页的问题
chroot rootdir systemctl enable systemd-resolved
ln -sf /run/systemd/resolve/stub-resolv.conf rootdir/etc/resolv.conf

# 3. 配置声卡主线上游 UCM 音频软链接对齐总线
mkdir -p rootdir/usr/share/alsa/ucm2/conf.d/sm8550
if [ -d rootdir/usr/share/alsa/ucm2/vbat-snd-card ]; then
    ln -sf ../vbat-snd-card rootdir/usr/share/alsa/ucm2/conf.d/sm8550/vbat-snd-card
fi

# 4. 阻止休眠挂起（防止平板进桌面后一息屏直接导致主线内核挂起死机）
mkdir -p rootdir/etc/systemd/sleep.conf.d
cat > rootdir/etc/systemd/sleep.conf.d/disable-suspend.conf <<EOF
[Sleep]
AllowSuspend=no
AllowHibernation=no
AllowSuspendThenHibernate=no
AllowHybridSleep=no
EOF

# 5. 注入平板横屏触控校准规则
mkdir -p rootdir/etc/udev/rules.d/
cat > rootdir/etc/udev/rules.d/99-touchscreen-sheng.rules <<EOF
ENV{ID_INPUT_TOUCHSCREEN}=="1", ENV{LIBINPUT_CALIBRATION_MATRIX}="1 0 0 0 1 0 0 0 1"
EOF
# ========================================================

# root password
chroot rootdir bash -c "echo -e '1234\n1234' | passwd root"

echo "xiaomi-$FLAVOUR-$MODE" > rootdir/etc/hostname

# =========================
# 🖥️ DESKTOP
# =========================
if [ "$distro_variant" = "desktop" ]; then

    if [ "$FLAVOUR" = "lomiri" ]; then
        chroot rootdir apt install -y \
            lomiri lomiri-desktop-session lomiri-system-settings \
            lightdm lightdm-gtk-greeter firefox-esr

        chroot rootdir systemctl disable gdm3 2>/dev/null || true
        chroot rootdir systemctl enable lightdm

    elif [ "$FLAVOUR" = "gnome" ]; then
        chroot rootdir apt install -y \
            gnome-shell gnome-session gnome-terminal gdm3 firefox-esr

        chroot rootdir systemctl enable gdm3
    fi

    # user与用户组提权
    chroot rootdir useradd -m -s /bin/bash luser
    echo "luser:luser" | chroot rootdir chpasswd
    chroot rootdir usermod -aG sudo,audio,video,render,input,plugdev luser

    # autologin
    if [ "$FLAVOUR" = "lomiri" ]; then
        mkdir -p rootdir/etc/lightdm/lightdm.conf.d
        cat > rootdir/etc/lightdm/lightdm.conf.d/50-autologin.conf <<EOF
[Seat:*]
autologin-user=luser
autologin-user-timeout=0
user-session=lomiri
greeter-session=lightdm-gtk-greeter
EOF

    else
        mkdir -p rootdir/etc/gdm3
        cat > rootdir/etc/gdm3/daemon.conf <<EOF
[daemon]
AutomaticLoginEnable=true
AutomaticLogin=luser
EOF
    fi

    chroot rootdir systemctl enable NetworkManager
    chroot rootdir systemctl set-default graphical.target
fi

# =========================
# 💽 FSTAB
# =========================
if [ "$MODE" = "dual" ]; then
    echo "PARTLABEL=linux / ext4 defaults,noatime,errors=remount-ro 0 1" > rootdir/etc/fstab
else
    echo "PARTLABEL=userdata / ext4 defaults,noatime,errors=remount-ro 0 1" > rootdir/etc/fstab
fi

# clean
chroot rootdir apt clean

# unmount
umount rootdir/dev/pts || true
umount rootdir/dev || true
umount rootdir/proc || true
umount rootdir/sys || true
umount rootdir || true

rm -rf rootdir

# uuid
tune2fs -U $FILESYSTEM_UUID "$ROOTFS_IMG"

echo "✅ DONE: $ROOTFS_IMG"

# compress
echo "🗜️ compressing..."
7z a "${ROOTFS_IMG}.7z" "$ROOTFS_IMG"

done
done
