#!/bin/bash
set -e

IMAGE_SIZE="8G"
FILESYSTEM_UUID="ee8d3593-59b1-480e-a3b6-4fefb17ee7d8"
DEBIAN_SUITE="beige"
DEBIAN_MIRROR="https://community-packages.deepin.com/beige/"

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
ROOTFS_IMG="deepin25_1_0_desktop_${TIMESTAMP}.img"

echo "=========================================="
echo "⏳ 开始构建最前沿版 Deepin 25.1.0 RootFS"
echo "🌟 模式: 完整桌面 + Kernel上游固件 + Debian Sid 最新 Mesa 3D驱动"
echo "内核版本: $KERNEL"
echo "=========================================="

rm -rf rootdir || true
truncate -s $IMAGE_SIZE "$ROOTFS_IMG"
mkfs.ext4 "$ROOTFS_IMG"
mkdir rootdir
mount -o loop "$ROOTFS_IMG" rootdir

if [ ! -f "/usr/share/debootstrap/scripts/${DEBIAN_SUITE}" ]; then
    ln -sf /usr/share/debootstrap/scripts/sid "/usr/share/debootstrap/scripts/${DEBIAN_SUITE}"
fi

debootstrap --no-check-gpg --arch=arm64 "$DEBIAN_SUITE" rootdir "$DEBIAN_MIRROR"

mount --bind /dev rootdir/dev
mount --bind /dev/pts rootdir/dev/pts
mount -t proc proc rootdir/proc
mount -t sysfs sys rootdir/sys

# 主源也使用了 trusted=yes
printf "deb [trusted=yes] %s %s main commercial community\n" "$DEBIAN_MIRROR" "$DEBIAN_SUITE" > rootdir/etc/apt/sources.list

# 强制 DNS 防断网
rm -f rootdir/etc/resolv.conf
echo "nameserver 8.8.8.8" > rootdir/etc/resolv.conf
echo "nameserver 1.1.1.1" >> rootdir/etc/resolv.conf
echo "nameserver 114.114.114.114" >> rootdir/etc/resolv.conf

chroot rootdir apt update

if ls *.deb 1> /dev/null 2>&1; then
    cp *.deb rootdir/tmp/
    chroot rootdir bash -c "apt install -y /tmp/*.deb || apt-get install -f -y"
fi

chroot rootdir apt install -y --no-install-recommends \
    deepin-keyring systemd systemd-resolved sudo vim-tiny wget curl network-manager wpasupplicant dbus locales initramfs-tools

# 恢复 DNS
rm -f rootdir/etc/resolv.conf
echo "nameserver 8.8.8.8" > rootdir/etc/resolv.conf
echo "nameserver 1.1.1.1" >> rootdir/etc/resolv.conf

# 完美中文底座配置
echo "🇨🇳 正在注入原生中文语言环境..."
chroot rootdir bash -c "echo 'LANG=zh_CN.UTF-8' > /etc/default/locale"
chroot rootdir sed -i 's/# zh_CN.UTF-8 UTF-8/zh_CN.UTF-8 UTF-8/' /etc/locale.gen
chroot rootdir locale-gen zh_CN.UTF-8

chroot rootdir bash -c "echo -e '1234\n1234' | passwd root"
echo "deepin-sheng" > rootdir/etc/hostname

# 🚨 使用 core 包拉取完整桌面生态
echo "🖥️ 正在拉取 Deepin 完整桌面生态与中文字体..."
chroot rootdir bash -c "apt install -y deepin-desktop-environment-core dde-session-shell dde-dock dde-launcher dde-desktop dde-control-center lightdm xwayland deepin-kwin-wayland xserver-xorg xinit fonts-noto-cjk fonts-wqy-microhei || apt install -y deepin-desktop-environment-core dde-session-shell lightdm xwayland deepin-kwin-wayland xserver-xorg xinit fonts-noto-cjk fonts-wqy-microhei"

# 🚀 [立大功的核弹级修复] 提取骁龙专属闭源固件
echo "📥 正在从 Kernel.org 上游提取骁龙 8 Gen 2 (sm8550) 专属闭源固件..."
mkdir -p rootdir/tmp/linux-fw
git clone --depth 1 --filter=blob:none --sparse https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git rootdir/tmp/linux-fw
git -C rootdir/tmp/linux-fw sparse-checkout set qcom
mkdir -p rootdir/lib/firmware/
cp -a rootdir/tmp/linux-fw/qcom rootdir/lib/firmware/
rm -rf rootdir/tmp/linux-fw
echo "✅ 骁龙核心固件注入完成！"

# 🚀 [终极杀招修正] 临时跨源拉取 Debian Sid，强制信任！
echo "📥 正在跨源拉取最新版 Mesa 3D 图形栈，以点亮 Adreno 740..."
# 🚨 关键修复：加入 [trusted=yes] 强行绕过 GPG 密钥检查
echo "deb [trusted=yes] http://deb.debian.org/debian sid main" > rootdir/etc/apt/sources.list.d/sid.list
chroot rootdir apt update
# 强制使用 -t sid 安装最新的显卡驱动
chroot rootdir apt install -y -t sid libgl1-mesa-dri libglx-mesa0 libegl-mesa0 mesa-vulkan-drivers mesa-utils
# 拔树寻根：用完立刻删掉 sid 源，防止后续 apt upgrade 搞崩 Deepin
rm -f rootdir/etc/apt/sources.list.d/sid.list
chroot rootdir apt update
echo "✅ 满血版 Mesa 3D 驱动注入完毕！"

chroot rootdir useradd -m -s /bin/bash luser
echo "luser:luser" | chroot rootdir chpasswd
chroot rootdir usermod -aG sudo,audio,video,render,input luser

chroot rootdir bash -c "echo 'ttyMSM0' >> /etc/securetty"
ln -sf /lib/systemd/system/getty@.service rootdir/etc/systemd/system/getty.target.wants/getty@ttyMSM0.service

if [ -f "rootdir/lib/firmware/ath12k/WCN7850/hw2.0/board-2.bin" ]; then
    cp rootdir/lib/firmware/ath12k/WCN7850/hw2.0/board-2.bin rootdir/lib/firmware/ath12k/WCN7850/hw2.0/board.bin
fi

chroot rootdir systemctl enable systemd-resolved
ln -sf /run/systemd/resolve/stub-resolv.conf rootdir/etc/resolv.conf

mkdir -p rootdir/etc/udev/rules.d/
printf 'ENV{ID_INPUT_TOUCHSCREEN}=="1", ENV{LIBINPUT_CALIBRATION_MATRIX}="1 0 0 0 1 0 0 0 1"\n' > rootdir/etc/udev/rules.d/99-touchscreen-sheng.rules

# ================= 🌌 图形界面智能配置 =================
echo "🌌 配置全局 Wayland/X11 智能引导引擎..."
cat <<EOF > rootdir/etc/profile.d/wayland-force.sh
export XDG_SESSION_TYPE=wayland
export QT_QPA_PLATFORM="wayland;xcb"
export MOZ_ENABLE_WAYLAND=1
export WLR_NO_HARDWARE_CURSORS=1
EOF
chmod +x rootdir/etc/profile.d/wayland-force.sh

mkdir -p rootdir/etc/lightdm/lightdm.conf.d
cat <<EOF > rootdir/etc/lightdm/lightdm.conf.d/12-autologin.conf
[Seat:*]
autologin-user=luser
autologin-user-timeout=0
EOF

WAYLAND_SESSION=$(ls rootdir/usr/share/wayland-sessions/*.desktop 2>/dev/null | head -n 1 | awk -F'/' '{print $NF}' | sed 's/\.desktop//' || true)

if [ -n "$WAYLAND_SESSION" ]; then
    echo "user-session=$WAYLAND_SESSION" >> rootdir/etc/lightdm/lightdm.conf.d/12-autologin.conf
    echo "✅ 智能探测成功！检测到 Wayland 会话名为: $WAYLAND_SESSION"
else
    echo "user-session=dde-x11" >> rootdir/etc/lightdm/lightdm.conf.d/12-autologin.conf
    echo "⚠️ 警告：未检测到 Wayland 会话，强制回退至 X11 保证亮屏"
fi

chroot rootdir systemctl enable lightdm
chroot rootdir systemctl set-default graphical.target

chroot rootdir systemctl mask deepin-login-sound.service || true
chroot rootdir systemctl mask deepin-login-sound-service.service || true
chroot rootdir bash -c "sed -i 's/quiet splash//g' /etc/default/grub" 2>/dev/null || true

# 强制在 initramfs 极早期加载高通显示驱动 (KMS)
echo "msm" >> rootdir/etc/initramfs-tools/modules
echo "gpu_sched" >> rootdir/etc/initramfs-tools/modules
echo "panel_edp" >> rootdir/etc/initramfs-tools/modules
# =========================================================

printf "PARTLABEL=linux / ext4 defaults,noatime,errors=remount-ro 0 1\n" > rootdir/etc/fstab

echo "🔄 强制重新生成 initramfs 引导镜像..."
chroot rootdir bash -c "update-initramfs -u -k all"

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
7z a "deepin25_1_0_desktop_${TIMESTAMP}.7z" "$ROOTFS_IMG"
rm -f "$ROOTFS_IMG"

echo "🎉 终极满血 3D 硬件加速版构建完成！"
