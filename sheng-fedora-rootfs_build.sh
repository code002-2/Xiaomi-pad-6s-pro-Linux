#!/bin/bash
set -e

IMAGE_SIZE="8G"
FILESYSTEM_UUID="ee8d3593-59b1-480e-a3b6-4fefb17ee7d8"
FEDORA_VERSION="44" 

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
ROOTFS_IMG="fedora_desktop_${TIMESTAMP}.img"

echo "=========================================="
echo "⏳ 开始构建纯净桌面版 Fedora ${FEDORA_VERSION} ARM RootFS"
echo "内核版本: $KERNEL"
echo "=========================================="

rm -rf rootdir || true
truncate -s $IMAGE_SIZE "$ROOTFS_IMG"
mkfs.ext4 "$ROOTFS_IMG"
mkdir rootdir
mount -o loop "$ROOTFS_IMG" rootdir

echo "⬇️ 正在通过 Docker 提取 Fedora ${FEDORA_VERSION} 基础根文件系统..."
docker pull --platform linux/arm64 fedora:${FEDORA_VERSION}
docker create --name fedora-temp fedora:${FEDORA_VERSION}
docker export fedora-temp | tar -x -C rootdir/
docker rm fedora-temp

mount --bind /dev rootdir/dev
mount --bind /dev/pts rootdir/dev/pts
mount -t proc proc rootdir/proc
mount -t sysfs sys rootdir/sys

rm -f rootdir/etc/resolv.conf
echo "nameserver 8.8.8.8" > rootdir/etc/resolv.conf
echo "nameserver 1.1.1.1" >> rootdir/etc/resolv.conf

echo "📦 正在更新 Fedora 系统并安装基础组件..."
# 排除官方内核，避免 dracut 报错并加快速度。加入编译工具。
chroot rootdir dnf -y update --exclude=kernel*
chroot rootdir dnf -y install --exclude=kernel* \
    systemd sudo vim wget curl tar xz pciutils findutils \
    NetworkManager wpa_supplicant dialog \
    git gcc make kernel-headers

echo "🔨 正在从高通官方源码现场编译 qrtr 服务..."
chroot rootdir bash -c "cd /tmp && git clone https://github.com/linux-msm/qrtr.git && cd qrtr && make prefix=/usr install && rm -rf /tmp/qrtr"

echo "🖥️ 正在安装 GNOME 桌面环境..."
# 精准命中 GNOME 桌面底层包组
chroot rootdir dnf -y install @gnome-desktop
chroot rootdir dnf -y install gdm

echo "🔨 正在扫描并注入本地内核与系统固件包..."
if ls *.deb 1> /dev/null 2>&1; then
    for pkg in *.deb; do
        echo "   -> 正在提取并覆盖注入 $pkg ..."
        dpkg-deb --fsys-tarfile "$pkg" | tar -x --keep-directory-symlink -C rootdir/
    done
    
    echo "   正在更新内核模块依赖..."
    KERNEL_MODULE_DIR=$(ls rootdir/usr/lib/modules/ | head -n 1)
    if [ -n "$KERNEL_MODULE_DIR" ]; then
        chroot rootdir /usr/sbin/depmod -a "$KERNEL_MODULE_DIR" || true
    fi
fi

if ls *.tar.gz 1> /dev/null 2>&1; then
    for tarball in *.tar.gz; do
        tar -xz --keep-directory-symlink -f "$tarball" -C rootdir/
    done
fi

chroot rootdir bash -c "echo 'root:1234' | chpasswd"
echo "fedora-sheng" > rootdir/etc/hostname

chroot rootdir useradd -m -s /bin/bash luser
chroot rootdir bash -c "echo 'luser:luser' | chpasswd"
chroot rootdir usermod -aG wheel,audio,video,input luser

echo "%wheel ALL=(ALL:ALL) NOPASSWD: ALL" > rootdir/etc/sudoers.d/wheel
chmod 440 rootdir/etc/sudoers.d/wheel

echo "🩹 注入 Fedora 底层自愈补丁..."
ln -sf /usr/lib/systemd/system/getty@.service rootdir/etc/systemd/system/getty.target.wants/getty@ttyMSM0.service

chroot rootdir systemctl enable systemd-resolved
chroot rootdir systemctl enable NetworkManager

mkdir -p rootdir/etc/udev/rules.d/
printf 'ENV{ID_INPUT_TOUCHSCREEN}=="1", ENV{LIBINPUT_CALIBRATION_MATRIX}="1 0 0 0 1 0 0 0 1"\n' > rootdir/etc/udev/rules.d/99-touchscreen-sheng.rules


# ==========================================
# 🚨 Fedora 桌面防崩溃与登录循环修复
# ==========================================
echo "🩹 正在注入 Fedora 专属桌面防崩溃补丁..."

# 1. 彻底禁用 SELinux (防止登录无限循环)
mkdir -p rootdir/etc/selinux
echo "SELINUX=disabled" > rootdir/etc/selinux/config
echo "SELINUXTYPE=targeted" >> rootdir/etc/selinux/config

# 2. GDM 自动登录配置 + 强制回退 X11 (防止高通驱动跑 Wayland 闪退)
mkdir -p rootdir/etc/gdm
printf "[daemon]\nAutomaticLoginEnable=True\nAutomaticLogin=luser\nWaylandEnable=false\n" > rootdir/etc/gdm/custom.conf
chroot rootdir systemctl enable gdm
chroot rootdir systemctl set-default graphical.target
# ==========================================


# ==========================================
# ✨ 高通 WiFi 专属一键自动修复魔法
# ==========================================
echo "⚙️ 正在预配置高通 WiFi 固件修复与驱动适配..."

FW_DIR="rootdir/usr/lib/firmware/ath12k/WCN7850/hw2.0"
if [ -f "$FW_DIR/board-2.bin" ]; then
    cp "$FW_DIR/board-2.bin" "$FW_DIR/board.bin"
fi

MOD_DIR="rootdir/usr/lib/modules"
TARGET_VER="7.0.0-sm8550-gf273227fab85"

if [ -d "$MOD_DIR" ]; then
    for dir in "$MOD_DIR"/*; do
        if [ -d "$dir" ] && [ "$(basename "$dir")" != "$TARGET_VER" ]; then
            mv "$dir" "$MOD_DIR/$TARGET_VER"
            chroot rootdir /usr/sbin/depmod -a "$TARGET_VER" || true
            break
        fi
    done
fi

echo "⚙️ 正在创建 qrtr 守护进程开机自启服务..."
cat << 'EOF' > rootdir/etc/systemd/system/qrtr-force.service
[Unit]
Description=Qualcomm IPC Router Service (QRTR)
After=network.target

[Service]
ExecStart=/usr/bin/qrtr-ns -f
Restart=always

[Install]
WantedBy=multi-user.target
EOF

chroot rootdir systemctl enable qrtr-force.service
# ==========================================

printf "PARTLABEL=linux / ext4 defaults,noatime,errors=remount-ro 0 1\n" > rootdir/etc/fstab

chroot rootdir dnf clean all

echo "🧹 正在清理后台遗留进程并安全卸载..."
fuser -k -9 -m rootdir || true
sleep 2

umount -l rootdir/dev/pts || true
umount -l rootdir/dev || true
umount -l rootdir/proc || true
umount -l rootdir/sys || true
umount -l rootdir || true
sleep 2
rm -rf rootdir

tune2fs -U $FILESYSTEM_UUID "$ROOTFS_IMG"

SPARSE_IMG="sparse_${ROOTFS_IMG}"
img2simg "$ROOTFS_IMG" "$SPARSE_IMG"
7z a "fedora_desktop_${TIMESTAMP}.7z" "$SPARSE_IMG"
rm -f "$ROOTFS_IMG" "$SPARSE_IMG"

echo "🎉 Fedora 44 版本构建圆满成功！"
