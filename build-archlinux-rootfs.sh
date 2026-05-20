#!/bin/bash
set -e

IMAGE_SIZE="4G"
FILESYSTEM_UUID="ee8d3593-59b1-480e-a3b6-4fefb17ee7d8"

usage() {
    echo "用法: $0 <server|desktop>"
    exit 1
}
[ $# -ne 1 ] && usage

VARIANT=$1
if [[ "$VARIANT" != "server" && "$VARIANT" != "desktop" ]]; then
    echo "错误: variant 必须是 server 或 desktop"
    exit 1
fi

if [ "$(id -u)" -ne 0 ]; then
    echo "请使用root权限运行"
    exit 1
fi

TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
ROOTFS_IMG="archlinux_${VARIANT}_${TIMESTAMP}.img"

echo "=========================================="
echo "开始构建 Arch Linux RootFS ($VARIANT)"
echo "=========================================="

# 安装 qemu-user-static 如果缺失
if ! command -v qemu-aarch64-static &> /dev/null; then
    apt-get update && apt-get install -y qemu-user-static
fi

rm -rf rootdir || true

# 创建空镜像并挂载
truncate -s $IMAGE_SIZE "$ROOTFS_IMG"
mkfs.ext4 "$ROOTFS_IMG"
mkdir rootdir
mount -o loop "$ROOTFS_IMG" rootdir

# 创建基础目录
mkdir -p rootdir/usr/bin
mkdir -p rootdir/var/lib/pacman
mkdir -p rootdir/etc/pacman.d/gnupg
mkdir -p rootdir/dev
mkdir -p rootdir/proc
mkdir -p rootdir/sys
mkdir -p rootdir/tmp

# 复制 QEMU 静态二进制
cp $(which qemu-aarch64-static) rootdir/usr/bin/

# 配置 pacman (Arch Linux ARM 源)
cat > rootdir/etc/pacman.conf <<'EOF'
[options]
Architecture = aarch64
SigLevel = Never
[core]
Server = http://mirror.archlinuxarm.org/$arch/$repo
[extra]
Server = http://mirror.archlinuxarm.org/$arch/$repo
[community]
Server = http://mirror.archlinuxarm.org/$arch/$repo
EOF

# 挂载虚拟文件系统
mount --bind /dev rootdir/dev
mount -t proc proc rootdir/proc
mount -t sysfs sys rootdir/sys

# 在 chroot 内执行引导脚本
cat > rootdir/bootstrap.sh <<'EOF'
#!/bin/bash
set -e
echo "初始化 pacman 密钥环..."
pacman-key --init
pacman-key --populate archlinuxarm
echo "安装基础系统..."
pacman -Syu --noconfirm --needed base base-devel
if [ "$1" = "desktop" ]; then
    pacman -S --noconfirm --needed xorg-server plasma-desktop sddm firefox
fi
systemctl enable systemd-networkd systemd-resolved
if [ "$1" = "desktop" ]; then
    systemctl enable sddm
else
    systemctl enable sshd
fi
EOF
chmod +x rootdir/bootstrap.sh

chroot rootdir /usr/bin/qemu-aarch64-static /bin/bash /bootstrap.sh "$VARIANT"

# 创建用户（桌面版）
if [ "$VARIANT" = "desktop" ]; then
    cat > rootdir/create_user.sh <<'EOF'
useradd -m -G wheel -s /bin/bash arch
echo "arch:arch" | chpasswd
echo "arch ALL=(ALL) ALL" >> /etc/sudoers
EOF
    chmod +x rootdir/create_user.sh
    chroot rootdir /usr/bin/qemu-aarch64-static /bin/bash /create_user.sh
    rm -f rootdir/create_user.sh
fi

# 设置主机名
echo "arch-${VARIANT}" > rootdir/etc/hostname

# 清理
rm -f rootdir/bootstrap.sh
rm -f rootdir/usr/bin/qemu-aarch64-static
chroot rootdir pacman -Scc --noconfirm 2>/dev/null || true

# 卸载
umount rootdir/dev rootdir/proc rootdir/sys 2>/dev/null || true
umount rootdir || true
rm -rf rootdir

# 固定 UUID
tune2fs -U $FILESYSTEM_UUID "$ROOTFS_IMG"

echo "✅ 镜像生成: $ROOTFS_IMG"
echo "🗜️ 压缩中..."
7z a "${ROOTFS_IMG}.7z" "$ROOTFS_IMG"
echo "🎉 完成！输出文件: ${ROOTFS_IMG}.7z"
