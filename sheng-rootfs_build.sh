#!/bin/bash
set -e

IMAGE_SIZE="8G"
FILESYSTEM_UUID="ee8d3593-59b1-480e-a3b6-4fefb17ee7d8"

# 🚨 增加了启动模式和桌面环境两个参数
if [ $# -lt 2 ] || [ $# -gt 4 ]; then
    echo "用法: $0 <distro-variant> <kernel_version> [boot_mode] [desktop_env]"
    echo "示例: $0 debian-desktop 7.1 dual kde"
    echo "      $0 debian-desktop 7.1 all all"
    exit 1
fi

if [ "$(id -u)" -ne 0 ]; then
    echo "❌ 请使用 root 权限运行此脚本！"
    exit 1
fi

DISTRO=$1
KERNEL=$2
TARGET_MODE=${3:-all}
TARGET_FLAVOUR=${4:-all} # 默认同时打包 GNOME 和 KDE

distro_type=$(echo "$DISTRO" | cut -d'-' -f1)
distro_variant=$(echo "$DISTRO" | cut -d'-' -f2)

if [ "$distro_type" != "debian" ]; then
    echo "❌ 目前仅支持 debian 衍生版"
    exit 1
fi

distro_version="trixie"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

# ==========================================
# 🎛️ 动态解析构建矩阵 (Boot Mode & Desktop)
# ==========================================
if [ "$TARGET_MODE" = "all" ]; then
    BOOTMODES=("dual" "single")
elif [[ "$TARGET_MODE" =~ ^(dual|single)$ ]]; then
    BOOTMODES=("$TARGET_MODE")
else
    echo "❌ 不支持的启动模式: $TARGET_MODE (仅支持 dual, single, all)"
    exit 1
fi

if [ "$TARGET_FLAVOUR" = "all" ]; then
    FLAVOURS=("gnome" "kde")
elif [[ "$TARGET_FLAVOUR" =~ ^(gnome|kde|lomiri)$ ]]; then
    FLAVOURS=("$TARGET_FLAVOUR")
else
    echo "❌ 不支持的桌面环境: $TARGET_FLAVOUR (仅支持 gnome, kde, lomiri, all)"
    exit 1
fi

# ==========================================
# 🛡️ 容错防线：无论发生什么，确保安全卸载
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

# 🚀 启动二维构建矩阵
for FLAVOUR in "${FLAVOURS[@]}"; do
    for MODE in "${BOOTMODES[@]}"; do

        echo ""
        echo "======================================"
        echo "🚀 开始构建: Debian $distro_version | 桌面: ${FLAVOUR^^} | 模式: $MODE"
        echo "======================================"

        ROOTFS_IMG="${distro_type}_${distro_version}_${FLAVOUR}_${MODE}_${TIMESTAMP}.img"

        # 确保环境干净
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

        # 🚨 核心网络修复：注入 DNS 防止 apt 卡死
        rm -f rootdir/etc/resolv.conf
        echo "nameserver 8.8.8.8" > rootdir/etc/resolv.conf
        echo "nameserver 1.1.1.1" >> rootdir/etc/resolv.conf
        echo "nameserver 223.5.5.5" >> rootdir/etc/resolv.conf

        echo "📦 正在安装基础环境组件..."
        chroot rootdir bash -c "export DEBIAN_FRONTEND=noninteractive && apt-get update && apt-get install -y --no-install-recommends systemd sudo vim wget curl network-manager openssh-server wpasupplicant dbus locales dialog"

        # ==========================================
        # 🌏 注入全面中文环境与时区
        # ==========================================
        echo "🌏 正在配置系统中文语言、字体与输入法..."
        
        sed -i 's/^# *\(en_US.UTF-8\)/\1/' rootdir/etc/locale.gen
        sed -i 's/^# *\(zh_CN.UTF-8\)/\1/' rootdir/etc/locale.gen
        chroot rootdir locale-gen
        
        echo "LANG=zh_CN.UTF-8" > rootdir/etc/default/locale
        echo "LANG=zh_CN.UTF-8" > rootdir/etc/locale.conf
        
        chroot rootdir ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
        
        chroot rootdir bash -c "export DEBIAN_FRONTEND=noninteractive && apt-get install -y fonts-noto-cjk fonts-wqy-microhei fonts-wqy-zenhei fcitx5 fcitx5-chinese-addons fcitx5-frontend-gtk3 fcitx5-frontend-qt5"
        
        cat > rootdir/etc/environment <<EOF
GTK_IM_MODULE=fcitx
QT_IM_MODULE=fcitx
XMODIFIERS=@im=fcitx
EOF

        echo "📦 正在注入并安装设备专属 .deb 驱动包..."
        wget -q https://github.com/code002-2/Xiaomi-pad-6s-pro-Linux/releases/download/mipps/xiaomi-mipps-auth_0.11_arm64.deb
        cp *.deb rootdir/tmp/

        chroot rootdir bash -c "export DEBIAN_FRONTEND=noninteractive && apt-get install -y libglib2.0-0 libprotobuf-c1 libqmi-glib5 libmbim-glib4 initramfs-tools"
        chroot rootdir bash -c "export DEBIAN_FRONTEND=noninteractive && apt-get install -y /tmp/*.deb" || echo "⚠️ 部分 .deb 安装出现警告，请检查依赖关系。"
        
        echo "✅ 自定义驱动安装完毕！"

        chroot rootdir bash -c "echo 'root:1234' | chpasswd"
        echo "debian-$FLAVOUR-$MODE" > rootdir/etc/hostname

        # =========================
        # 🖥️ 桌面环境部署分发器
        # =========================
        if [ "$distro_variant" = "desktop" ]; then
            
            chroot rootdir useradd -m -s /bin/bash luser || true
            chroot rootdir bash -c "echo 'luser:luser' | chpasswd"
            chroot rootdir usermod -aG sudo,audio,video,input luser

            if [ "$FLAVOUR" = "lomiri" ]; then
                echo "🖥️ 安装 Lomiri (Ubuntu Touch) 桌面..."
                chroot rootdir bash -c "export DEBIAN_FRONTEND=noninteractive && apt-get install -y lomiri lomiri-desktop-session lomiri-system-settings lightdm lightdm-gtk-greeter firefox-esr"
                
                chroot rootdir systemctl disable gdm3 2>/dev/null || true
                chroot rootdir systemctl enable lightdm

                mkdir -p rootdir/etc/lightdm/lightdm.conf.d
                cat > rootdir/etc/lightdm/lightdm.conf.d/50-autologin.conf <<EOF
[Seat:*]
autologin-user=luser
autologin-user-timeout=0
user-session=lomiri
greeter-session=lightdm-gtk-greeter
EOF

            elif [ "$FLAVOUR" = "gnome" ]; then
                echo "🖥️ 安装 GNOME 桌面环境..."
                chroot rootdir bash -c "export DEBIAN_FRONTEND=noninteractive && apt-get install -y gnome-shell gnome-session gnome-terminal gdm3 firefox-esr gnome-tweaks nautilus"
                
                chroot rootdir systemctl enable gdm3
                
                mkdir -p rootdir/etc/gdm3
                cat > rootdir/etc/gdm3/daemon.conf <<EOF
[daemon]
AutomaticLoginEnable=true
AutomaticLogin=luser
EOF

            # 🚨 新增：KDE Plasma 注入逻辑
            elif [ "$FLAVOUR" = "kde" ]; then
                echo "🖥️ 安装 KDE Plasma 桌面环境 (支持 Wayland)..."
                chroot rootdir bash -c "export DEBIAN_FRONTEND=noninteractive && apt-get install -y kde-plasma-desktop plasma-workspace-wayland sddm konsole dolphin ark gwenview firefox-esr"
                chroot rootdir systemctl enable sddm
                
                # 配置 SDDM 自动登录 Wayland 桌面
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

        # =========================
        # 🏁 清理与生成镜像
        # =========================
        echo "🧹 正在清理 apt 缓存以减小镜像体积..."
        chroot rootdir apt-get clean
        rm -f rootdir/tmp/*.deb

        cleanup_mounts

        tune2fs -U $FILESYSTEM_UUID "$ROOTFS_IMG"

        echo "🔄 正在转换为 Fastboot 专用稀疏镜像 (Sparse Image)..."
        SPARSE_IMG="sparse_${ROOTFS_IMG}"
        img2simg "$ROOTFS_IMG" "$SPARSE_IMG"

        echo "🗜️ 正在执行高压压缩..."
        7z a "${ROOTFS_IMG%.img}.7z" "$SPARSE_IMG"

        rm -f "$ROOTFS_IMG" "$SPARSE_IMG"
        
        echo "🎉 [$FLAVOUR - $MODE] 版本构建完成！产物: ${ROOTFS_IMG%.img}.7z"

    done
done

trap - EXIT ERR INT TERM
echo "✅ 所有指定的 Debian 镜像已全部打包完毕！"