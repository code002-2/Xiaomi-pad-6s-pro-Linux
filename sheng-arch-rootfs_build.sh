#!/bin/bash
set -euo pipefail

# =============================================================================
# sheng-arch-rootfs_build.sh — Arch Linux ARM rootfs builder (refactored)
# =============================================================================
source "$(dirname "$0")/lib/rootfs-common.sh"

# --- Distro-specific configuration ---
IMAGE_SIZE="8G"
UUID="ee8d3593-59b1-480e-a3b6-4fefb17ee7d8"
ALARM_MIRROR="https://mirror.archlinuxarm.org"

# --- Password configuration (override via env vars) ---
ROOT_PASS="${ROOT_PASS:-1234}"
USER_PASS="${USER_PASS:-luser}"
USER_NAME="${USER_NAME:-luser}"

# --- Argument parsing ---
if [ $# -lt 2 ] || [ $# -gt 4 ]; then
    echo "用法: $0 <distro_name> <kernel_version> [desktop_environment] [boot_mode]"
    echo "示例: $0 arch 7.1.0-rc6 kde dual"
    exit 1
fi
if [ "$(id -u)" -ne 0 ]; then
    echo "错误: 必须使用 root 权限运行此脚本！"
    exit 1
fi

DISTRO=$1
KERNEL=$2
TARGET_DE=${3:-gnome}
TARGET_MODE=${4:-all}
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

DESKTOPS=()
if [ "$TARGET_DE" = "all" ]; then
    DESKTOPS=("gnome" "kde")
elif [[ "$TARGET_DE" =~ ^(gnome|kde)$ ]]; then
    DESKTOPS=("$TARGET_DE")
else
    echo "错误: 不支持的选项: $TARGET_DE (仅支持 gnome, kde, all)"
    exit 1
fi

if [ "$TARGET_MODE" = "all" ]; then
    BOOTMODES=("dual" "single")
elif [[ "$TARGET_MODE" =~ ^(dual|single)$ ]]; then
    BOOTMODES=("$TARGET_MODE")
else
    echo "错误: 不支持的启动模式: $TARGET_MODE"
    exit 1
fi

# --- Main build loop ---
for DE in "${DESKTOPS[@]}"; do
    for MODE in "${BOOTMODES[@]}"; do
        ROOTFS_IMG="${DISTRO}_${DE}_${MODE}_${TIMESTAMP}.img"
        echo ""
        echo "=========================================="
        echo "开始执行 -> 桌面: ${DE^^} | 模式: $MODE | 目标: $ROOTFS_IMG"
        echo "=========================================="

        # Pre-flight checks
        preflight_checks 10240

        # Step 1: Create image
    create_image "$IMAGE_SIZE" "$ROOTFS_IMG" "$UUID"
    setup_chroot_mounts "$ROOTDIR"
    trap_teardown "$ROOTDIR"

    echo "正在初始化 Arch 基础系统..."
    if [ ! -f "ArchLinuxARM-aarch64-latest.tar.gz" ]; then
        wget "https://os.archlinuxarm.org/os/ArchLinuxARM-aarch64-latest.tar.gz" || {
            echo "错误: 下载 Arch Linux ARM 基础系统失败" >&2
            exit 1
        }
    fi
    bsdtar -xpf ArchLinuxARM-aarch64-latest.tar.gz -C "$ROOTDIR" || {
        echo "错误: 解压 Arch Linux ARM 基础系统失败" >&2
        exit 1
    }

    echo "Server = $ALARM_MIRROR/\$arch/\$repo" > "$ROOTDIR/etc/pacman.d/mirrorlist"

    chroot "$ROOTDIR" pacman-key --init
    chroot "$ROOTDIR" pacman-key --populate archlinuxarm
    sed -i 's/^#DisableDownloadTimeout/DisableDownloadTimeout/' "$ROOTDIR/etc/pacman.conf"

    chroot "$ROOTDIR" pacman -Rdd --noconfirm linux-aarch64 linux-firmware || true
    chroot "$ROOTDIR" pacman -Syu --noconfirm base kmod glibc systemd sudo vim wget curl networkmanager wpa_supplicant dbus qrtr dialog

    # Step 3: Desktop environment
    echo "正在安装 ${DE^^} 桌面环境..."
    if [ "$DE" = "gnome" ]; then
        chroot "$ROOTDIR" bash -c "pacman -Sgq gnome | grep -vE 'gnome-books|gnome-boxes' | pacman -S --noconfirm --needed - gdm gnome-tweaks"
        setup_autologin "$ROOTDIR" "gnome" "$USER_NAME"
    elif [ "$DE" = "kde" ]; then
        chroot "$ROOTDIR" pacman -S --noconfirm --needed plasma-meta sddm konsole dolphin ark gwenview
        setup_autologin "$ROOTDIR" "kde" "$USER_NAME"
    fi
    chroot "$ROOTDIR" systemctl set-default graphical.target

    # Step 4: Kernel injection
    echo "正在注入本地内核与生成 Initramfs..."
    if ls *.deb 1> /dev/null 2>&1; then
        for pkg in *.deb; do
            echo "   -> 注入包: $pkg"
            dpkg-deb --fsys-tarfile "$pkg" | tar -x --keep-directory-symlink -C "$ROOTDIR/"
        done

        KERNEL_MODULE_DIR=$(detect_kernel_module_dir "$ROOTDIR")
        if [ -n "$KERNEL_MODULE_DIR" ]; then
            chroot "$ROOTDIR" /usr/bin/depmod -a "$KERNEL_MODULE_DIR" || true
            chroot "$ROOTDIR" pacman -S --noconfirm --needed mkinitcpio
            sed -i 's/autodetect[^,]*//g' "$ROOTDIR/etc/mkinitcpio.conf"
            chroot "$ROOTDIR" mkinitcpio -k "$KERNEL_MODULE_DIR" -g "/boot/initramfs-linux.img"
            if [ -f "$ROOTDIR/boot/vmlinuz-$KERNEL_MODULE_DIR" ]; then
                cp "$ROOTDIR/boot/vmlinuz-$KERNEL_MODULE_DIR" "$ROOTDIR/boot/Image"
            fi
        fi
    else
        echo "错误: 当前目录下未找到任何 .deb 内核包，无法生成可启动 rootfs！" >&2
        exit 1
    fi

    # Step 5: System quirks
    echo "正在配置硬件补丁与账户权限..."
    echo 'en_US.UTF-8 UTF-8' > "$ROOTDIR/etc/locale.gen"
    chroot "$ROOTDIR" /usr/bin/locale-gen
    echo 'LANG=en_US.UTF-8' > "$ROOTDIR/etc/locale.conf"
    echo "arch-${DE}-sheng" > "$ROOTDIR/etc/hostname"

    setup_users "$ROOTDIR" "$ROOT_PASS" "$USER_NAME" "$USER_PASS" "wheel,audio,video,input"
    echo "%wheel ALL=(ALL:ALL) NOPASSWD: ALL" > "$ROOTDIR/etc/sudoers.d/wheel"
    chmod 440 "$ROOTDIR/etc/sudoers.d/wheel"

    chroot "$ROOTDIR" systemctl enable systemd-resolved NetworkManager

    # QRTR service — 使用公共库统一创建
    setup_qrtr_service "$ROOTDIR"

    setup_getty_ttyMSM0 "$ROOTDIR"
    configure_touchscreen "$ROOTDIR"
    fix_wifi_firmware "$ROOTDIR"

    # Step 6: fstab & cleanup
    generate_fstab "$ROOTDIR" "$MODE"
    chroot "$ROOTDIR" pacman -Scc --noconfirm
    teardown_mounts "$ROOTDIR"

    # Step 7: Pack
    apply_fs_uuid "$UUID" "$ROOTFS_IMG"
    pack_sparse_image "$ROOTFS_IMG" "${ROOTFS_IMG%.img}.7z"

    echo "${DE^^} - $MODE 版本构建完成！产物: ${ROOTFS_IMG%.img}.7z"
    done
done

rm -f ArchLinuxARM-aarch64-latest.tar.gz
echo "所有指定的桌面环境和启动模式构建任务已全部结束！"
