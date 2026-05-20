 #!/bin/bash
set -e

# ============================================
# Ubuntu 25.04 (Plucky) RootFS 构建脚本
# 用途：为小米K20 Pro等arm64设备生成可启动镜像
# 依赖：debootstrap, 7z, 内核deb包
# ============================================

IMAGE_SIZE="8G"
FILESYSTEM_UUID="ee8d3593-59b1-480e-a3b6-4fefb17ee7d8"

# Ubuntu 25.04 配置
UBUNTU_SUITE="plucky"
UBUNTU_MIRROR="http://archive.ubuntu.com/ubuntu"

usage() {
    echo "用法: $0 <variant> <kernel_version>"
    echo "variant: server 或 desktop"
    echo "kernel_version: 例如 7.0 (对应kernel-bundle-7.0中的.deb包)"
    exit 1
}

if [ $# -lt 2 ]; then
    usage
fi

if [ "$(id -u)" -ne 0 ]; then
    echo "请使用root权限运行"
    exit 1
fi

VARIANT=$1      # server 或 desktop
KERNEL=$2

if [[ "$VARIANT" != "server" && "$VARIANT" != "desktop" ]]; then
    echo "错误: variant 必须是 server 或 desktop"
    exit 1
fi

TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
ROOTFS_IMG="ubuntu25_${VARIANT}_${TIMESTAMP}.img"

echo "=========================================="
echo "开始构建 Ubuntu 25.04 (Plucky) RootFS"
echo "变体: $VARIANT"
echo "内核版本: $KERNEL"
echo "镜像: $ROOTFS_IMG"
echo "=========================================="

# 清理旧目录
rm -rf rootdir || true

# 创建空白ext4镜像
truncate -s $IMAGE_SIZE "$ROOTFS_IMG"
mkfs.ext4 "$ROOTFS_IMG"

# 挂载
mkdir rootdir
mount -o loop "$ROOTFS_IMG" rootdir

# debootstrap 基础系统
debootstrap --arch=arm64 "$UBUNTU_SUITE" rootdir "$UBUNTU_MIRROR"

# 挂载虚拟文件系统
mount --bind /dev rootdir/dev
mount --bind /dev/pts rootdir/dev/pts
mount -t proc proc rootdir/proc
mount -t sysfs sys rootdir/sys

# 复制并安装内核包
if ls *.deb 1> /dev/null 2>&1; then
    cp *.deb rootdir/tmp/
    echo "安装内核及驱动包..."
    chroot rootdir bash -c "apt update && apt install -y /tmp/*.deb || true"
else
    echo "警告: 未找到任何.deb包，请确保当前目录有内核bundle"
fi

# 基础包安装
chroot rootdir apt update
chroot rootdir apt install -y \
    systemd sudo vim wget curl \
    network-manager openssh-server \
    wpasupplicant dbus ubuntu-drivers-common

# 设置root密码
chroot rootdir bash -c "echo -e '1234\n1234' | passwd root"

# 主机名
echo "ubuntu25-${VARIANT}" > rootdir/etc/hostname

# =========================
# 桌面环境配置
# =========================
if [ "$VARIANT" = "desktop" ]; then
    chroot rootdir apt install -y \
        ubuntu-desktop-minimal \
        gnome-terminal \
        firefox \
        gdm3

    # 创建普通用户
    chroot rootdir useradd -m -s /bin/bash luser
    echo "luser:luser" | chroot rootdir chpasswd
    chroot rootdir usermod -aG sudo luser

    # GDM自动登录
    mkdir -p rootdir/etc/gdm3
    cat > rootdir/etc/gdm3/daemon.conf <<EOF
[daemon]
AutomaticLoginEnable=true
AutomaticLogin=luser
EOF

    chroot rootdir systemctl enable gdm3
    chroot rootdir systemctl set-default graphical.target
else
    # 服务器版：启用SSH和网络
    chroot rootdir systemctl enable ssh
    chroot rootdir systemctl enable NetworkManager
    chroot rootdir systemctl set-default multi-user.target
fi

# =========================
# fstab (适配Android双启动)
# =========================
cat > rootdir/etc/fstab <<EOF
PARTLABEL=linux / ext4 defaults 0 1
EOF

# 清理缓存
chroot rootdir apt clean

# 卸载
umount rootdir/dev/pts || true
umount rootdir/dev || true
umount rootdir/proc || true
umount rootdir/sys || true
umount rootdir || true
rm -rf rootdir

# 固定UUID
tune2fs -U $FILESYSTEM_UUID "$ROOTFS_IMG"

echo "✅ 镜像生成: $ROOTFS_IMG"

# 压缩
echo "🗜️ 压缩中..."
7z a "${ROOTFS_IMG}.7z" "$ROOTFS_IMG"

echo "🎉 完成！输出文件: ${ROOTFS_IMG}.7z"
