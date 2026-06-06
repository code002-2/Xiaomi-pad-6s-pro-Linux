#!/bin/bash
set -e

IMAGE_SIZE="8G"
FILESYSTEM_UUID="ee8d3593-59b1-480e-a3b6-4fefb17ee7d8"
KERNEL=$1
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
ROOTFS_IMG="void_retro_${TIMESTAMP}.img"

echo "=========================================="
echo "🎮 Void Retro Gaming OS"
echo "=========================================="

# 基础清理与创建
rm -rf rootdir || true
truncate -s $IMAGE_SIZE "$ROOTFS_IMG"
mkfs.ext4 -F "$ROOTFS_IMG"
mkdir rootdir
mount -o loop "$ROOTFS_IMG" rootdir

# 拉取底包
VOID_REPO="https://repo-default.voidlinux.org/live/current"
LATEST_TAR=$(curl -s "$VOID_REPO/" | grep -o 'void-aarch64-ROOTFS-[0-9]*.tar.xz' | head -n 1)
wget -q "$VOID_REPO/$LATEST_TAR"
tar -xpf "$LATEST_TAR" -C rootdir/
rm -f "$LATEST_TAR"

mount --bind /dev rootdir/dev
mount --bind /dev/pts rootdir/dev/pts
mount -t proc proc rootdir/proc
mount -t sysfs sys rootdir/sys

echo "📦 正在强行覆盖安装最新版 xbps..."
mkdir -p /tmp/xbps-update
# 这里的 URL 获取最新的 xbps 二进制包
XBPS_PACKAGE_URL=$(curl -s "https://repo-default.voidlinux.org/current/aarch64/" | grep -o 'xbps-[0-9\.]*_[0-9]*\.aarch64\.xbps' | head -n 1)
wget -q "https://repo-default.voidlinux.org/current/aarch64/$XBPS_PACKAGE_URL" -O /tmp/xbps-update/xbps.xbps
# xbps 包本质就是 tar.xz，直接强力解包到 rootdir 根目录，跳过所有校验！
cd /tmp/xbps-update && xxbps-deb-like-extract-hack() {
    # xbps 解包工具
    xbin/xbps-xunpack -f xbps.xbps -C rootdir/
}
# 如果系统里没有 xunpack 工具，我们用 bsdtar 暴力拆解 (因为 .xbps 就是个压缩包)
bsdtar -xf /tmp/xbps-update/xbps.xbps -C rootdir/
cd -

# 现在 xbps 已经是最新的了，剩下的安装就顺滑了
chroot rootdir xbps-install -Syu -y
chroot rootdir xbps-install -y \
    sudo nano wget curl pciutils findutils \
    NetworkManager wpa_supplicant dbus kmod dracut \
    xorg-minimal xorg-server xinit mesa-dri \
    retroarch qrtr


# 🔨 强行注入 Deb 内核 (带绝对版本锁)
if ls *.deb 1> /dev/null 2>&1; then
    for pkg in *.deb; do
        dpkg-deb --fsys-tarfile "$pkg" | tar -x --keep-directory-symlink -C rootdir/
    done
    REAL_KERNEL_VER=$(ls rootdir/boot/vmlinuz-* 2>/dev/null | head -n 1 | sed -e 's/.*vmlinuz-//')
    chroot rootdir /usr/sbin/depmod -a "$REAL_KERNEL_VER"
    chroot rootdir dracut -N --kver "$REAL_KERNEL_VER" --force "/boot/initramfs-linux.img"
    cp "rootdir/boot/vmlinuz-$REAL_KERNEL_VER" "rootdir/boot/Image"
fi

# 🔑 密码注入 (SHA-512)
chroot rootdir useradd -m -s /bin/bash luser
echo "luser:$(openssl passwd -6 'luser')" | chroot rootdir chpasswd -e
echo "root:$(openssl passwd -6 '1234')" | chroot rootdir chpasswd -e
chroot rootdir usermod -aG wheel,audio,video,input luser
echo "%wheel ALL=(ALL:ALL) NOPASSWD: ALL" > rootdir/etc/sudoers.d/wheel

# 🎮 自动启动配置
cat << 'EOF' > rootdir/home/luser/.xinitrc
exec retroarch
EOF
chroot rootdir chown luser:luser /home/luser/.xinitrc

# 🛠️ Runit 服务 (QRTR + NetworkManager)
mkdir -p rootdir/etc/sv/qrtr-ns
cat << 'EOF' > rootdir/etc/sv/qrtr-ns/run
#!/bin/sh
[ -x /usr/bin/qrtr-ns ] && exec /usr/bin/qrtr-ns -f
EOF
chmod +x rootdir/etc/sv/qrtr-ns/run
mkdir -p rootdir/etc/runit/runsvdir/default
ln -sf /etc/sv/qrtr-ns rootdir/etc/runit/runsvdir/default/
ln -sf /etc/sv/NetworkManager rootdir/etc/runit/runsvdir/default/

# 🧹 清理收尾
fuser -k -9 -m rootdir || true
umount -l rootdir/dev/pts rootdir/dev rootdir/proc rootdir/sys rootdir
tune2fs -U $FILESYSTEM_UUID "$ROOTFS_IMG"
img2simg "$ROOTFS_IMG" "sparse_${ROOTFS_IMG}"
7z a "void_retro_${TIMESTAMP}.7z" "sparse_${ROOTFS_IMG}"
