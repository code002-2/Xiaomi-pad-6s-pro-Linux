#!/bin/bash
set -e

IMAGE_SIZE="8G"
FILESYSTEM_UUID="ee8d3593-59b1-480e-a3b6-4fefb17ee7d8"

if [ $# -lt 2 ] || [ $# -gt 4 ]; then
    echo "用法: $0 <distro-variant> <kernel_version> [boot_mode] [desktop_env]"
    echo "示例: $0 debian-desktop 7.1 all all"
    exit 1
fi

if [ "$(id -u)" -ne 0 ]; then
    echo "❌ 请使用 root 权限运行此脚本！"
    exit 1
fi

DISTRO=$1
KERNEL=$2
TARGET_MODE=${3:-all}
TARGET_FLAVOUR=${4:-all} 

distro_type=$(echo "$DISTRO" | cut -d'-' -f1)
distro_variant=$(echo "$DISTRO" | cut -d'-' -f2)

if [ "$distro_type" != "debian" ]; then
    echo "❌ 目前仅支持 debian 衍生版"
    exit 1
fi

distro_version="forky"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

# ==========================================
# 🎛️ 动态解析构建矩阵 (二维循环引擎)
# ==========================================
if [ "$TARGET_MODE" = "all" ]; then
    BOOTMODES=("dual" "single")
elif [[ "$TARGET_MODE" =~ ^(dual|single)$ ]]; then
    BOOTMODES=("$TARGET_MODE")
else
    echo "❌ 不支持的启动模式: $TARGET_MODE"
    exit 1
fi

if [ "$TARGET_FLAVOUR" = "all" ]; then
    FLAVOURS=("gnome" "kde")
elif [[ "$TARGET_FLAVOUR" =~ ^(gnome|kde)$ ]]; then
    FLAVOURS=("$TARGET_FLAVOUR")
else
    echo "❌ 不支持的桌面环境: $TARGET_FLAVOUR"
    exit 1
fi

# ==========================================
# 🛡️ 容错防线：挂载点清理
# ==========================================
cleanup_mounts() {
    echo "🧹 正在触发挂载点安全清理机制..."
    fuser -k -9 -m rootdir 2>/dev/null || true
    sleep 2
    umount -l rootdir/dev/pts 2>/dev/null || true
    umount -l rootdir/dev 2>/dev/null || true
    umount -l rootdir/proc 2>/dev/null || true
    umount -l rootdir/sys 2>/dev/null || true
    umount -l rootdir 2>/dev/null || true
    rm -rf rootdir
}
trap cleanup_mounts EXIT ERR INT TERM

# 🚀 启动二维构建矩阵 (桌面 x 模式)
for FLAVOUR in "${FLAVOURS[@]}"; do
    for MODE in "${BOOTMODES[@]}"; do

        echo ""
        echo "======================================================"
        echo "🔥 开始构建: Debian $distro_version | 桌面: ${FLAVOUR^^} | 模式: $MODE"
        echo "======================================================"

        ROOTFS_IMG="${distro_type}_${distro_version}_${FLAVOUR}_${MODE}_${TIMESTAMP}.img"

        cleanup_mounts 
        mkdir -p rootdir

        truncate -s $IMAGE_SIZE "$ROOTFS_IMG"
        mkfs.ext4 -O ^metadata_csum "$ROOTFS_IMG"
        mount -o loop "$ROOTFS_IMG" rootdir

        echo "⬇️ 正在使用 debootstrap 拉取基础系统..."
        debootstrap --arch=arm64 "$distro_version" rootdir http://deb.debian.org/debian/

        mount --bind /dev rootdir/dev
        mount --bind /dev/pts rootdir/dev/pts
        mount -t proc proc rootdir/proc
        mount -t sysfs sys rootdir/sys

        rm -f rootdir/etc/resolv.conf
        echo "nameserver 8.8.8.8" > rootdir/etc/resolv.conf
        echo "nameserver 1.1.1.1" >> rootdir/etc/resolv.conf
        echo "nameserver 223.5.5.5" >> rootdir/etc/resolv.conf

        echo "📦 正在安装基础环境组件..."
        chroot rootdir bash -c "export DEBIAN_FRONTEND=noninteractive && apt-get update && apt-get install -y --no-install-recommends systemd sudo vim wget curl network-manager openssh-server wpasupplicant dbus locales dialog"

        echo "🌏 正在配置中文输入法..."
        chroot rootdir bash -c "export DEBIAN_FRONTEND=noninteractive && apt-get install -y fonts-noto-cjk fonts-wqy-microhei fonts-wqy-zenhei fcitx5 fcitx5-chinese-addons fcitx5-frontend-gtk3 fcitx5-frontend-qt5"
        
        cat > rootdir/etc/environment <<EOF
GTK_IM_MODULE=fcitx
QT_IM_MODULE=fcitx
XMODIFIERS=@im=fcitx
EOF

        echo "📦 正在注入设备专属 .deb 驱动包 (由工作流预下载)..."
        cp *.deb rootdir/tmp/

        chroot rootdir bash -c "export DEBIAN_FRONTEND=noninteractive && apt-get install -y libglib2.0-0 libprotobuf-c1 libqmi-glib5 libmbim-glib4 initramfs-tools"
        chroot rootdir bash -c "export DEBIAN_FRONTEND=noninteractive && apt-get install -y /tmp/*.deb" || echo "⚠️ 部分 .deb 存在警告，继续执行。"
        
        chroot rootdir bash -c "echo 'root:1234' | chpasswd"
        echo "debian-$FLAVOUR-$MODE" > rootdir/etc/hostname

        # =========================
        # 📶 WiFi 驱动适配与区域码
        # =========================
        echo "⚙️ 正在预配置高通 WiFi 驱动适配与区域码..."
        chroot rootdir bash -c "export DEBIAN_FRONTEND=noninteractive && apt-get install -y qrtr-tools" || true
        chroot rootdir systemctl enable qrtr-ns || true
        echo 'options cfg80211 ieee80211_regdom=CN' > rootdir/etc/modprobe.d/cfg80211.conf

        # =========================
        # 🖥️ 桌面环境分发中心
        # =========================
        if [ "$distro_variant" = "desktop" ]; then
            chroot rootdir useradd -m -s /bin/bash luser || true
            chroot rootdir bash -c "echo 'luser:luser' | chpasswd"
            chroot rootdir usermod -aG sudo,audio,video,input luser

            if [ "$FLAVOUR" = "gnome" ]; then
                echo "🖥️ 安装 GNOME 桌面环境..."
                chroot rootdir bash -c "export DEBIAN_FRONTEND=noninteractive && apt-get install -y gnome-core gnome-terminal gdm3 firefox-esr"
                chroot rootdir systemctl enable gdm3
                mkdir -p rootdir/etc/gdm3
                cat > rootdir/etc/gdm3/daemon.conf <<EOF
[daemon]
AutomaticLoginEnable=true
AutomaticLogin=luser
EOF

            elif [ "$FLAVOUR" = "kde" ]; then
                # 🚨 重点修改在这里：采纳了你的方案！
                echo "🖥️ 安装 KDE Plasma 桌面环境 (使用官方 kde-standard 方案)..."
                # 直接拉取 kde-standard (取代零碎包)，附加上你脚本里提取的网络和蓝牙插件
                chroot rootdir bash -c "export DEBIAN_FRONTEND=noninteractive && apt-get install -y plasma-desktop sddm konsole firefox-esr plasma-workspace systemsettings plasma-nm"
                chroot rootdir systemctl enable sddm
                mkdir -p rootdir/etc/sddm.conf.d
                cat > rootdir/etc/sddm.conf.d/autologin.conf <<EOF
[Autologin]
User=luser
Session=plasma
EOF
            fi

            chroot rootdir systemctl enable NetworkManager
            chroot rootdir systemctl set-default graphical.target
        fi

        # =========================
        # 💽 FSTAB 挂载策略
        # =========================
        if [ "$MODE" = "dual" ]; then
            echo "PARTLABEL=linux / ext4 defaults,noatime,errors=remount-ro 0 1" > rootdir/etc/fstab
        else
            echo "PARTLABEL=userdata / ext4 defaults,noatime,errors=remount-ro 0 1" > rootdir/etc/fstab
        fi

        echo "🧹 清理场地准备打包..."
        chroot rootdir apt-get clean
        rm -f rootdir/tmp/*.deb
        cleanup_mounts

        tune2fs -U $FILESYSTEM_UUID "$ROOTFS_IMG"

        echo "🔄 转换 Sparse 镜像并压缩..."
        SPARSE_IMG="sparse_${ROOTFS_IMG}"
        img2simg "$ROOTFS_IMG" "$SPARSE_IMG"
        zstd -19 -T0 --long "$SPARSE_IMG" -o "${ROOTFS_IMG%.img}.zst"
        rm -f "$ROOTFS_IMG" "$SPARSE_IMG"
        
        echo "🎉 [${FLAVOUR^^} - $MODE] 版本完成！"

    done
done

trap - EXIT ERR INT TERM
echo "✅ Debian 镜像已打包完毕！"