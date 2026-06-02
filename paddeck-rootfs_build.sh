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
ROOTFS_IMG="paddeck_os_${TIMESTAMP}.img"

echo "=========================================="
echo "🎮 开始构建 PadDeck OS"
echo "内核版本: $KERNEL"
echo "=========================================="

rm -rf rootdir || true
truncate -s $IMAGE_SIZE "$ROOTFS_IMG"
mkfs.ext4 "$ROOTFS_IMG"
mkdir rootdir
mount -o loop "$ROOTFS_IMG" rootdir

debootstrap --arch=arm64 "$DEBIAN_SUITE" rootdir "$DEBIAN_MIRROR"

mount --bind /dev rootdir/dev
mount --bind /dev/pts rootdir/dev/pts
mount -t proc proc rootdir/proc
mount -t sysfs sys rootdir/sys

printf "deb %s %s main contrib non-free non-free-firmware\n" "$DEBIAN_MIRROR" "$DEBIAN_SUITE" > rootdir/etc/apt/sources.list
printf "deb %s %s-updates main contrib non-free non-free-firmware\n" "$DEBIAN_MIRROR" "$DEBIAN_SUITE" >> rootdir/etc/apt/sources.list
chroot rootdir apt update

# 注入底层工具与多媒体库
chroot rootdir apt install -y --no-install-recommends \
    systemd systemd-resolved sudo vim-tiny wget curl network-manager wpasupplicant dbus locales git 7zip unzip tar \
    libsdl2-2.0-0 libsdl2-mixer-2.0-0 libvpx7

chroot rootdir bash -c "echo 'LANG=en_US.UTF-8' > /etc/default/locale"
chroot rootdir sed -i 's/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
chroot rootdir locale-gen en_US.UTF-8

chroot rootdir bash -c "echo -e '1234\n1234' | passwd root"
echo "paddeck-sm8550" > rootdir/etc/hostname

echo "🎮 拉取游戏图形栈与微型合成器..."
chroot rootdir apt install -y --no-install-recommends \
    gamescope lightdm pipewire pipewire-pulse wireplumber \
    libgl1-mesa-dri libglx-mesa0 libegl-mesa0 mesa-vulkan-drivers mesa-utils \
    openbox xwayland mangohud

echo "📥 注入骁龙闭源固件..."
mkdir -p rootdir/tmp/linux-fw
git clone --depth 1 --filter=blob:none --sparse https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git rootdir/tmp/linux-fw
git -C rootdir/tmp/linux-fw sparse-checkout set qcom
mkdir -p rootdir/lib/firmware/
cp -a rootdir/tmp/linux-fw/qcom rootdir/lib/firmware/
rm -rf rootdir/tmp/linux-fw

# 创建玩家账户
chroot rootdir useradd -m -s /bin/bash luser
echo "luser:luser" | chroot rootdir chpasswd
chroot rootdir usermod -aG sudo,audio,video,render,input luser

# ================= 🚨 Steam ARM64 原生注入区 =================
echo "🚀 正在植入 Valve 官方 ARM64 Steam 客户端..."

chroot rootdir bash -c "ln -sf /usr/lib/aarch64-linux-gnu/libvpx.so.9 /usr/lib/aarch64-linux-gnu/libvpx.so.6"

mkdir -p rootdir/home/luser/.local/share/Steam/package
mkdir -p rootdir/home/luser/.local/share/Steam/compatibilitytools.d
mkdir -p rootdir/home/luser/.steam

wget -qO rootdir/tmp/steam_arm.zip https://client-update.steamstatic.com/bins_linuxarm64_linuxarm64.zip.f523fa87fc6b9b5435a5e7370cb0d664ef53b50b
unzip -q rootdir/tmp/steam_arm.zip -d rootdir/tmp/steam_arm_extracted
mv rootdir/tmp/steam_arm_extracted/steamrtarm64 rootdir/home/luser/.local/share/Steam/

echo "publicbeta" > rootdir/home/luser/.local/share/Steam/package/beta

chroot rootdir bash -c "ln -sf /home/luser/.local/share/Steam/linuxarm64 /home/luser/.steam/sdkarm64"

echo "📦 注入 Proton 11 ARM64 武器库..."
wget -qO rootdir/tmp/ARM64proton-Runtime64.tar.gz "https://github.com/code002-2/Xiaomi-pad-6s-pro-Linux/releases/download/app/ARM64proton-Runtime64.tar.gz"
tar -xzf rootdir/tmp/ARM64proton-Runtime64.tar.gz -C rootdir/home/luser/.local/share/Steam/compatibilitytools.d/

chmod -R u+rwx rootdir/home/luser/.local/share/Steam/steamrtarm64/
chroot rootdir chown -R luser:luser /home/luser/.local
chroot rootdir chown -R luser:luser /home/luser/.steam
# ==============================================================

chroot rootdir bash -c "echo 'ttyMSM0' >> /etc/securetty"
ln -sf /lib/systemd/system/getty@.service rootdir/etc/systemd/system/getty.target.wants/getty@ttyMSM0.service

chroot rootdir systemctl enable systemd-resolved
ln -sf /run/systemd/resolve/stub-resolv.conf rootdir/etc/resolv.conf

mkdir -p rootdir/etc/udev/rules.d/
printf 'ENV{ID_INPUT_TOUCHSCREEN}=="1", ENV{LIBINPUT_CALIBRATION_MATRIX}="1 0 0 0 1 0 0 0 1"\n' > rootdir/etc/udev/rules.d/99-touchscreen-sheng.rules

mkdir -p rootdir/etc/lightdm/lightdm.conf.d
cat <<EOF > rootdir/etc/lightdm/lightdm.conf.d/12-autologin.conf
[Seat:*]
autologin-user=luser
autologin-user-timeout=0
user-session=gamescope-session
EOF

# Gamescope 独占启动配置
mkdir -p rootdir/usr/share/wayland-sessions
cat <<EOF > rootdir/usr/share/wayland-sessions/gamescope-session.desktop
[Desktop Entry]
Name=PadDeck Game Mode
Comment=Start Steam directly via Gamescope
Exec=gamescope -W 3096 -H 1920 -r 144 -e -- /home/luser/.local/share/Steam/steamrtarm64/steam -tenfoot
Type=Application
EOF

chroot rootdir systemctl enable lightdm
chroot rootdir systemctl set-default graphical.target

printf "PARTLABEL=linux / ext4 defaults,noatime,errors=remount-ro 0 1\n" > rootdir/etc/fstab

chroot rootdir apt clean
chroot rootdir rm -rf /tmp/*

umount rootdir/dev/pts || true
umount rootdir/dev || true
umount rootdir/proc || true
umount rootdir/sys || true
umount rootdir || true
rm -rf rootdir

tune2fs -U $FILESYSTEM_UUID "$ROOTFS_IMG"

echo "✅ 镜像生成完成: $ROOTFS_IMG"
7z a "paddeck_os_sm8550_${TIMESTAMP}.7z" "$ROOTFS_IMG"
rm -f "$ROOTFS_IMG"

echo "🎉 PadDeck OS 构建成功！"
