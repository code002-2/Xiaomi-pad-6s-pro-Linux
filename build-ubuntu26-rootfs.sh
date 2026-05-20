#!/bin/bash
set -e

# ============================================
# Ubuntu 26.04 LTS (Resolute) RootFS 构建脚本
# 用途：为 arm64 设备生成可启动镜像
# 依赖：debootstrap, 7z, 内核deb包
# ============================================

IMAGE_SIZE="8G"
FILESYSTEM_UUID="ee8d3593-59b1-480e-a3b6-4fefb17ee7d8"

# Ubuntu 26.04 配置
UBUNTU_SUITE="resolute"
# 使用清华镜像源（国内快，且已同步26.04）
UBUNTU_MIRROR="https://mirrors.tuna.tsinghua.edu.cn/ubuntu"

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

VARIANT=$1
KERNEL=$2

if [[ "$VARIANT" != "server" && "$VARIANT" != "desktop" ]]; then
    echo "错误: variant 必须是 server 或 desktop"
    exit 1
fi

TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
ROOTFS_IMG="ubuntu26_${VARIANT}_${TIMESTAMP}.img"

echo "=========================================="
echo "开始构建 Ubuntu 26.04 (Resolute) RootFS"
echo "变体: $VARIANT"
echo "内核版本: $KERNEL"
echo "镜像: $ROOTFS_IMG"
echo "debootstrap 源: $UBUNTU_MIRROR"
echo "套件: $UBUNTU_SUITE"
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

# 写入完整的 apt 源配置（使用清华源）
cat > rootdir/etc/apt/sources.list <<EOF
deb $UBUNTU_MIRROR $UBUNTU_SUITE main restricted universe multiverse
deb $UBUNTU_MIRROR ${UBUNTU_SUITE}-updates main restricted universe multiverse
deb $UBUNTU_MIRROR ${UBUNTU_SUITE}-backports main restricted universe multiverse
deb $UBUNTU_MIRROR ${UBUNTU_SUITE}-security main restricted universe multiverse
EOF

chroot rootdir apt update

# 复制并安装内核包（如果存在）
if ls *.deb 1> /dev/null 2>&1; then
    cp *.deb rootdir/tmp/
    echo "安装内核及驱动包..."
    chroot rootdir bash -c "apt install -y /tmp/*.deb || true"
else
    echo "警告: 未找到任何.deb包，请确保内核bundle已下载"
fi

# 基础包安装（尽量最小化）
chroot rootdir apt install -y --no-install-recommends \
    systemd sudo vim-tiny wget curl \
    network-manager openssh-server \
    wpasupplicant dbus

# 设置root密码
chroot rootdir bash -c "echo -e '1234\n1234' | passwd root"

# 主机名
echo "ubuntu26-${VARIANT}" > rootdir/etc/hostname

# =========================
# 桌面环境配置
# =========================
if [ "$VARIANT" = "desktop" ]; then
    # 安装最小化桌面（GNOME）
    chroot rootdir apt install -y --no-install-recommends \
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
chroot rootdir rm -rf /tmp/*.deb

# 卸载挂载点
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
