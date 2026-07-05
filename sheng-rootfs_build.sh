#!/bin/bash
set -euo pipefail

# =============================================================================
# sheng-rootfs_build.sh — Debian Trixie rootfs builder (refactored)
# =============================================================================
source "$(dirname "$0")/lib/rootfs-common.sh"

# --- Distro-specific configuration ---
IMAGE_SIZE="8G"
DISTRO_VERSION="trixie"
MIRROR="https://deb.debian.org/debian/"
UUID="ee8d3593-59b1-480e-a3b6-4fefb17ee7d8"

# --- Password configuration (override via env vars) ---
ROOT_PASS="${ROOT_PASS:-1234}"
USER_PASS="${USER_PASS:-luser}"
USER_NAME="${USER_NAME:-luser}"

# --- Argument parsing ---
if [ $# -lt 2 ] || [ $# -gt 4 ]; then
    echo "用法: $0 <distro-variant> <kernel_version> [boot_mode] [desktop_env]"
    echo "示例: $0 debian-desktop 7.1 all all"
    exit 1
fi

if [ "$(id -u)" -ne 0 ]; then
    echo "错误: 请使用 root 权限运行此脚本！"
    exit 1
fi

DISTRO=$1
KERNEL=$2
TARGET_MODE=${3:-all}
TARGET_FLAVOUR=${4:-all}

distro_type=$(echo "$DISTRO" | cut -d'-' -f1)
distro_variant=$(echo "$DISTRO" | cut -d'-' -f2)

if [ "$distro_type" != "debian" ]; then
    echo "错误: 目前仅支持 debian 衍生版"
    exit 1
fi

TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

# --- Dynamic build matrix ---
if [ "$TARGET_MODE" = "all" ]; then
    BOOTMODES=("dual" "single")
elif [[ "$TARGET_MODE" =~ ^(dual|single)$ ]]; then
    BOOTMODES=("$TARGET_MODE")
else
    echo "错误: 不支持的启动模式: $TARGET_MODE"
    exit 1
fi

if [ "$TARGET_FLAVOUR" = "all" ]; then
    FLAVOURS=("gnome" "kde")
elif [[ "$TARGET_FLAVOUR" =~ ^(gnome|kde)$ ]]; then
    FLAVOURS=("$TARGET_FLAVOUR")
else
    echo "错误: 不支持的桌面环境: $TARGET_FLAVOUR"
    exit 1
fi

# --- Main build loop ---
for FLAVOUR in "${FLAVOURS[@]}"; do
    for MODE in "${BOOTMODES[@]}"; do
        echo ""
        echo "======================================================"
        echo "开始构建: Debian $DISTRO_VERSION | 桌面: ${FLAVOUR^^} | 模式: $MODE"
        echo "======================================================"

        ROOTFS_IMG="${distro_type}_${DISTRO_VERSION}_${FLAVOUR}_${MODE}_${TIMESTAMP}.img"

        # Step 1: Create image
        create_image "$IMAGE_SIZE" "$ROOTFS_IMG" "$UUID"
        setup_chroot_mounts "$ROOTDIR"
        setup_dns "$ROOTDIR" 8.8.8.8 1.1.1.1 223.5.5.5

        # Step 2: Bootstrap
        echo "正在使用 debootstrap 拉取基础系统..."
        debootstrap --arch=arm64 "$DISTRO_VERSION" "$ROOTDIR" "$MIRROR"

        # Step 3: Base packages
        echo "正在安装基础环境组件..."
        chroot "$ROOTDIR" bash -c "export DEBIAN_FRONTEND=noninteractive && apt-get update && apt-get install -y --no-install-recommends systemd sudo vim wget curl network-manager openssh-server wpasupplicant dbus locales dialog"

        # Step 4: Chinese locale & input
        echo "正在配置系统中文语言与输入法..."
        sed -i 's/^# *\(en_US.UTF-8\)/\1/' "$ROOTDIR/etc/locale.gen"
        sed -i 's/^# *\(zh_CN.UTF-8\)/\1/' "$ROOTDIR/etc/locale.gen"
        chroot "$ROOTDIR" locale-gen

        echo "LANG=zh_CN.UTF-8" > "$ROOTDIR/etc/default/locale"
        echo "LANG=zh_CN.UTF-8" > "$ROOTDIR/etc/locale.conf"
        chroot "$ROOTDIR" ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime

        chroot "$ROOTDIR" bash -c "export DEBIAN_FRONTEND=noninteractive && apt-get install -y fonts-noto-cjk fonts-wqy-microhei fonts-wqy-zenhei fcitx5 fcitx5-chinese-addons fcitx5-frontend-gtk3 fcitx5-frontend-qt5"

        cat > "$ROOTDIR/etc/environment" <<EOF
GTK_IM_MODULE=fcitx
QT_IM_MODULE=fcitx
XMODIFIERS=@im=fcitx
EOF

        # Step 5: Inject driver deb
        echo "正在注入设备专属 .deb 驱动包..."
        wget -q https://github.com/code002-2/Xiaomi-pad-6s-pro-Linux/releases/download/mipps/xiaomi-mipps-auth_0.11_arm64.deb
        cp *.deb "$ROOTDIR/tmp/"

        chroot "$ROOTDIR" bash -c "export DEBIAN_FRONTEND=noninteractive && apt-get install -y libglib2.0-0 libprotobuf-c1 libqmi-glib5 libmbim-glib4 initramfs-tools"
        chroot "$ROOTDIR" bash -c "export DEBIAN_FRONTEND=noninteractive && apt-get install -y /tmp/*.deb" || echo "警告: 部分 .deb 存在警告，继续执行。"

        # Step 6: Users & hostname
        setup_users "$ROOTDIR" "$ROOT_PASS" "$USER_NAME" "$USER_PASS" "sudo,audio,video,input"
        echo "debian-$FLAVOUR-$MODE" > "$ROOTDIR/etc/hostname"

        # Step 7: Desktop environment
        if [ "$distro_variant" = "desktop" ]; then
            if [ "$FLAVOUR" = "gnome" ]; then
                echo "安装 GNOME 桌面环境..."
                chroot "$ROOTDIR" bash -c "export DEBIAN_FRONTEND=noninteractive && apt-get install -y gnome-shell gnome-session gnome-terminal gdm3 firefox-esr gnome-tweaks nautilus"
                chroot "$ROOTDIR" systemctl enable gdm3
                mkdir -p "$ROOTDIR/etc/gdm3"
                cat > "$ROOTDIR/etc/gdm3/daemon.conf" <<EOF
[daemon]
AutomaticLoginEnable=true
AutomaticLogin=$USER_NAME
EOF

            elif [ "$FLAVOUR" = "kde" ]; then
                echo "安装 KDE Plasma 桌面环境..."
                chroot "$ROOTDIR" bash -c "export DEBIAN_FRONTEND=noninteractive && apt-get install -y kde-standard sddm plasma-nm bluedevil firefox-esr"
                chroot "$ROOTDIR" systemctl enable sddm
                mkdir -p "$ROOTDIR/etc/sddm.conf.d"
                cat > "$ROOTDIR/etc/sddm.conf.d/autologin.conf" <<EOF
[Autologin]
User=$USER_NAME
Session=plasma
EOF
            fi

            chroot "$ROOTDIR" systemctl enable NetworkManager
            chroot "$ROOTDIR" systemctl set-default graphical.target
        fi

        # Step 8: Hardware quirks
        setup_getty_ttyMSM0 "$ROOTDIR"
        configure_touchscreen "$ROOTDIR"
        fix_wifi_firmware "$ROOTDIR"

        # Step 9: fstab
        generate_fstab "$ROOTDIR" "$MODE"

        # Step 10: Cleanup & pack
        echo "清理场地准备打包..."
        chroot "$ROOTDIR" apt-get clean
        rm -f "$ROOTDIR/tmp"/*.deb
        teardown_mounts "$ROOTDIR"

        apply_fs_uuid "$UUID" "$ROOTFS_IMG"

        echo "转换 Sparse 镜像并压缩..."
        pack_sparse_image "$ROOTFS_IMG" "${ROOTFS_IMG%.img}.7z"

        echo "[${FLAVOUR^^} - $MODE] 版本完成！"
    done
done

echo "✅ Debian 镜像已打包完毕！"
