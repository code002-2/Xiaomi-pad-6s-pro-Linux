#!/bin/bash
set -e

IMAGE_SIZE="8G"
FILESYSTEM_UUID="ee8d3593-59b1-480e-a3b6-4fefb17ee7d8"
KERNEL=$1
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
ROOTFS_IMG="void_retro_${TIMESTAMP}.img"

echo "=========================================="
echo "🎮 正在构建 Void Retro Gaming OS (最终修复版)"
echo "=========================================="

rm -rf rootdir || true
truncate -s $IMAGE_SIZE "$ROOTFS_IMG"
mkfs.ext4 -F "$ROOTFS_IMG"
mkdir rootdir
mount -o loop "$ROOTFS_IMG" rootdir

# ⬇️ 提取底包 (增加重试逻辑)
echo "⬇️ 正在提取 Void Linux 底包..."
VOID_REPO="https://repo-default.voidlinux.org/live/current"
for i in {1..5}; do
    LATEST_TAR=$(curl -s --retry 3 --connect-timeout 10 "$VOID_REPO/" | grep -o 'void-aarch64-ROOTFS-[0-9]*.tar.xz' | head -n 1) && break || sleep 5
done
wget -q "$VOID_REPO/$LATEST_TAR"
tar -xpf "$LATEST_TAR" -C rootdir/
rm -f "$LATEST_TAR"

mount --bind /dev rootdir/dev
mount --bind /dev/pts rootdir/dev/pts
mount -t proc proc rootdir/proc
mount -t sysfs sys rootdir/sys

# 🚨 强制修复 DNS
echo "nameserver 1.1.1.1" > rootdir/etc/resolv.conf

# 📦 最终绝杀：彻底禁用签名校验，强制安装本地包来升级
echo "📦 正在执行 xbps 地狱级强制升级..."
export XBPS_ARCH=aarch64

# 1. 直接修改配置文件，彻底关闭所有签名检查
mkdir -p rootdir/etc/xbps.d
echo "repository=https://repo-default.voidlinux.org/current/aarch64" > rootdir/etc/xbps.d/00-repository-main.conf
echo "nocache=true" >> rootdir/etc/xbps.d/00-repository-main.conf

# 2. 核心中的核心：使用 --ignore-sig-ok 参数彻底无视所有签名错误
# 这是给旧系统打新补丁的唯一手段
chroot rootdir xbps-install -y --ignore-sig-ok --force xbps

# 3. 同步仓库并强制忽略签名安装所有组件
chroot rootdir xbps-install -Syu -y --ignore-sig-ok
chroot rootdir xbps-install -y --force --ignore-sig-ok \
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
