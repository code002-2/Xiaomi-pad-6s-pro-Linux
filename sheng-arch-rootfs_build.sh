#!/bin/bash
set -e

IMAGE_SIZE="8G"
FILESYSTEM_UUID="ee8d3593-59b1-480e-a3b6-4fefb17ee7d8"
ALARM_MIRROR="http://mirror.archlinuxarm.org"

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
ROOTFS_IMG="archlinux_desktop_${TIMESTAMP}.img"

echo "=========================================="
echo "⏳ 开始构建纯净桌面版 Arch Linux ARM RootFS"
echo "内核版本: $KERNEL"
echo "=========================================="

rm -rf rootdir || true
truncate -s $IMAGE_SIZE "$ROOTFS_IMG"
mkfs.ext4 "$ROOTFS_IMG"
mkdir rootdir
mount -o loop "$ROOTFS_IMG" rootdir

echo "⬇️ 正在下载 Arch Linux ARM (aarch64) 基础包..."
wget -q http://os.archlinuxarm.org/os/ArchLinuxARM-aarch64-latest.tar.gz
bsdtar -xpf ArchLinuxARM-aarch64-latest.tar.gz -C rootdir
rm ArchLinuxARM-aarch64-latest.tar.gz

mount --bind /dev rootdir/dev
mount --bind /dev/pts rootdir/dev/pts
mount -t proc proc rootdir/proc
mount -t sysfs sys rootdir/sys

# 强制写入公共 DNS
rm -f rootdir/etc/resolv.conf
echo "nameserver 8.8.8.8" > rootdir/etc/resolv.conf
echo "nameserver 1.1.1.1" >> rootdir/etc/resolv.conf

# 配置 Arch Linux ARM 全球镜像源
echo "Server = $ALARM_MIRROR/\$arch/\$repo" > rootdir/etc/pacman.d/mirrorlist

# 初始化 pacman 密钥环
chroot rootdir pacman-key --init
chroot rootdir pacman-key --populate archlinuxarm

# 禁用 pacman 的下载超时机制
sed -i 's/^#DisableDownloadTimeout/DisableDownloadTimeout/' rootdir/etc/pacman.conf

echo "🧹 正在清理 Arch 自带的内核与固件，为您提供的 Release 包保留空间..."
chroot rootdir pacman -Rdd --noconfirm linux-aarch64 linux-firmware || true

echo "📦 正在更新系统并安装基础组件..."
chroot rootdir pacman -Syu --noconfirm base kmod glibc systemd sudo vim wget curl networkmanager wpa_supplicant dbus

echo "🖥️ 正在安装 GNOME 桌面环境及依赖..."
chroot rootdir pacman -S --noconfirm gnome gdm

echo "🔨 正在扫描并注入本地内核与系统固件包 (鸠占鹊巢：覆盖官方组件)..."

# 使用 tar 的软链接保护机制完美合并 Debian 与 Arch 目录树，并覆盖原生包
if ls *.deb 1> /dev/null 2>&1; then
    for pkg in *.deb; do
        echo "   -> 正在提取并覆盖注入 $pkg ..."
        dpkg-deb --fsys-tarfile "$pkg" | tar -x --keep-directory-symlink -C rootdir/
    done
    
    echo "   正在更新内核模块依赖..."
    KERNEL_MODULE_DIR=$(ls rootdir/usr/lib/modules/ | head -n 1)
    if [ -n "$KERNEL_MODULE_DIR" ]; then
        echo "   发现内核版本: $KERNEL_MODULE_DIR"
        chroot rootdir /usr/bin/depmod -a "$KERNEL_MODULE_DIR" || true
    else
        echo "   ⚠️ 未能在 /usr/lib/modules/ 中找到内核模块目录。"
    fi
fi

# 处理所有的 .tar.gz 格式文件
if ls *.tar.gz 1> /dev/null 2>&1; then
    for tarball in *.tar.gz; do
        echo "   -> 正在解压系统包 $tarball ..."
        tar -xz --keep-directory-symlink -f "$tarball" -C rootdir/
    done
fi

# 确保固件目录存在并修正权限
if [ -d "rootdir/usr/lib/firmware" ]; then
    chmod -R 755 rootdir/usr/lib/firmware/ || true
fi

# 🌐 语言环境初始化
echo 'en_US.UTF-8 UTF-8' > rootdir/etc/locale.gen
chroot rootdir /usr/bin/locale-gen
echo 'LANG=en_US.UTF-8' > rootdir/etc/locale.conf

# 密码设置
chroot rootdir bash -c "echo 'root:1234' | chpasswd"

# 主机名完全调整为 arch-sheng
echo "arch-sheng" > rootdir/etc/hostname

# 创建普通用户并分配合规的硬件访问权限组
chroot rootdir useradd -m -s /bin/bash luser
chroot rootdir bash -c "echo 'luser:luser' | chpasswd"
chroot rootdir usermod -aG wheel,audio,video,input luser

# 赋予 wheel 组 sudo 权限
echo "%wheel ALL=(ALL:ALL) ALL" > rootdir/etc/sudoers.d/wheel
chmod 440 rootdir/etc/sudoers.d/wheel

echo "🩹 正在针对高通 SM8550 (Sheng) 注入底层自愈补丁..."
ln -sf /usr/lib/systemd/system/getty@.service rootdir/etc/systemd/system/getty.target.wants/getty@ttyMSM0.service

# 激活 DNS 托管解析与网络服务
chroot rootdir systemctl enable systemd-resolved
chroot rootdir systemctl enable NetworkManager
ln -sf /run/systemd/resolve/stub-resolv.conf rootdir/etc/resolv.conf

# 触控屏幕方向与矩阵校准规则
mkdir -p rootdir/etc/udev/rules.d/
printf 'ENV{ID_INPUT_TOUCHSCREEN}=="1", ENV{LIBINPUT_CALIBRATION_MATRIX}="1 0 0 0 1 0 0 0 1"\n' > rootdir/etc/udev/rules.d/99-touchscreen-sheng.rules

# GDM 自动登录配置
mkdir -p rootdir/etc/gdm
printf "[daemon]\nAutomaticLoginEnable=True\nAutomaticLogin=luser\n" > rootdir/etc/gdm/custom.conf
chroot rootdir systemctl enable gdm

# 强制进入图形化靶位
chroot rootdir systemctl set-default graphical.target

# ==========================================
# 🚨 挂载安全防线
# ==========================================
# 文件系统挂载对齐 (加入了 errors=remount-ro 容灾防线)
printf "PARTLABEL=linux / ext4 defaults,noatime,errors=remount-ro 0 1\n" > rootdir/etc/fstab

# 清理构建缓存
chroot rootdir pacman -Scc --noconfirm

# ==========================================
# 终极安全卸载与清理流程
# ==========================================
echo "🧹 正在清理后台遗留进程并安全卸载挂载点..."

# 1. 强行杀死 chroot 环境中遗留的任何幽灵进程
fuser -k -9 -m rootdir || true
sleep 2

# 2. 使用 -l (lazy) 懒卸载强行分离系统层
umount -l rootdir/dev/pts || true
umount -l rootdir/dev || true
umount -l rootdir/proc || true
umount -l rootdir/sys || true
umount -l rootdir || true

# 给内核一点时间同步文件系统日志
sleep 2

# 3. 安全删除挂载目录
rm -rf rootdir

tune2fs -U $FILESYSTEM_UUID "$ROOTFS_IMG"

echo "✅ 原始镜像生成完成: $ROOTFS_IMG"
echo "🔄 正在将其转换为 Fastboot 专用的稀疏镜像 (Sparse Image)..."
SPARSE_IMG="sparse_${ROOTFS_IMG}"
# 🚨 终极绝杀：利用 img2simg 生成可被 fastboot 直接识别的镜像格式
img2simg "$ROOTFS_IMG" "$SPARSE_IMG"

echo "🗜️ 正在生成最终 7z 压缩包..."
# 打包时仅保留转换后的稀疏镜像，体积大大减小
7z a "archlinux_desktop_${TIMESTAMP}.7z" "$SPARSE_IMG"

# 清理原始镜像和中间文件
rm -f "$ROOTFS_IMG" "$SPARSE_IMG"

echo "🎉 Fastboot 专用精简桌面版 Arch Linux ARM 自动化编译全部圆满成功！"
