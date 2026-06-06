#!/bin/bash
set -e

IMAGE_SIZE="8G"
FILESYSTEM_UUID="ee8d3593-59b1-480e-a3b6-4fefb17ee7d8"
KERNEL=$1
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
ROOTFS_IMG="void_retro_${TIMESTAMP}.img"

echo "=========================================="
echo "🎮 正在构建 Void Retro Gaming OS"
echo "=========================================="

# 🛡️ 容错清理
rm -rf rootdir || true
truncate -s $IMAGE_SIZE "$ROOTFS_IMG"
mkfs.ext4 "$ROOTFS_IMG"
mkdir rootdir
mount -o loop "$ROOTFS_IMG" rootdir

# ⬇️ 提取 Void Linux 底包
VOID_REPO="https://repo-default.voidlinux.org/live/current"
LATEST_TAR=$(curl -s "$VOID_REPO/" | grep -o 'void-aarch64-ROOTFS-[0-9]*.tar.xz' | head -n 1)
wget -q "$VOID_REPO/$LATEST_TAR"
tar -xpf "$LATEST_TAR" -C rootdir/
rm -f "$LATEST_TAR"

mount --bind /dev rootdir/dev
mount --bind /dev/pts rootdir/dev/pts
mount -t proc proc rootdir/proc
mount -t sysfs sys rootdir/sys

# 📦 安装必要组件
chroot rootdir xbps-install -Syu
chroot rootdir xbps-install -y \
    sudo nano wget curl pciutils findutils \
    NetworkManager wpa_supplicant dbus kmod dracut \
    xorg-minimal xorg-server xinit mesa-dri \
    retroarch retroarch-assets libretro-core-info qrtr

# 🔨 绝对路径锁定法注入内核
if ls *.deb 1> /dev/null 2>&1; then
    for pkg in *.deb; do
        dpkg-deb --fsys-tarfile "$pkg" | tar -x --keep-directory-symlink -C rootdir/
    done
    REAL_KERNEL_VER=$(ls rootdir/boot/vmlinuz-* 2>/dev/null | head -n 1 | sed -e 's/.*vmlinuz-//')
    chroot rootdir /usr/sbin/depmod -a "$REAL_KERNEL_VER"
    chroot rootdir dracut -N --kver "$REAL_KERNEL_VER" --force "/boot/initramfs-linux.img"
    cp "rootdir/boot/vmlinuz-$REAL_KERNEL_VER" "rootdir/boot/Image"
fi

chroot rootdir useradd -m -s /bin/bash luser
PASS_HASH=$(openssl passwd -6 "luser")
chroot rootdir usermod -p "$PASS_HASH" luser
chroot rootdir usermod -aG wheel,audio,video,input luser
ROOT_HASH=$(openssl passwd -6 "1234")
chroot rootdir usermod -p "$ROOT_HASH" root

echo "%wheel ALL=(ALL:ALL) NOPASSWD: ALL" > rootdir/etc/sudoers.d/wheel
# ==========================================

cat << 'EOF' > rootdir/home/luser/.xinitrc
#!/bin/sh
exec retroarch
EOF
chroot rootdir chown luser:luser /home/luser/.xinitrc

mkdir -p rootdir/etc/sv/qrtr-ns
cat << 'EOF' > rootdir/etc/sv/qrtr-ns/run
#!/bin/sh
sleep 3
[ -x /usr/bin/qrtr-ns ] && exec /usr/bin/qrtr-ns -f
EOF
chmod +x rootdir/etc/sv/qrtr-ns/run

ln -s /etc/sv/qrtr-ns rootdir/etc/runit/runsvdir/default/
ln -s /etc/sv/dbus rootdir/etc/runit/runsvdir/default/
ln -s /etc/sv/NetworkManager rootdir/etc/runit/runsvdir/default/

fuser -k -9 -m rootdir || true
umount -l rootdir/dev/pts rootdir/dev rootdir/proc rootdir/sys rootdir
tune2fs -U $FILESYSTEM_UUID "$ROOTFS_IMG"
img2simg "$ROOTFS_IMG" "sparse_${ROOTFS_IMG}"
7z a "void_retro_${TIMESTAMP}.7z" "sparse_${ROOTFS_IMG}"

echo "🎉 构建完毕！"
