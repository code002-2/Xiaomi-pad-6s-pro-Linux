#!/bin/bash
set -euo pipefail

# =============================================================================
# sheng-gaming-os_build.sh — ROCKNIX+Armada 混合游戏系统构建器
# =============================================================================
# 基于 Fedora 44 rootfs，添加 RetroArch + EmulationStation + Steam/FEX
# 输出 SD 卡刷写镜像
#
# 用法:
#   ./sheng-gaming-os_build.sh <kernel_version> [launcher] [output_type]
#
#   参数:
#     kernel_version  — 内核版本 (如 7.1, 7.1.4, latest)
#     launcher        — 启动器选择 (默认: both)
#                       retroarch  = 仅模拟器 (RetroArch + ES-DE)
#                       steam      = 仅 PC 游戏 (Steam + FEX)
#                       both       = 两者都有 (启动时选择)
#     output_type     — 输出类型 (默认: sd)
#                       sd         = SD 卡完整镜像
#                       image      = 仅 rootfs 镜像
# =============================================================================

source "$(dirname "$0")/lib/rootfs-common.sh"
source "$(dirname "$0")/lib/gaming-packages.sh"

# --- 配置 ---
FEDORA_VERSION="44"
FEDORA_CONTAINER_URL="https://download.fedoraproject.org/pub/fedora/linux/releases/${FEDORA_VERSION}/Container/aarch64/images/Fedora-Container-Base-Generic-${FEDORA_VERSION}-1.7.aarch64.oci.tar.xz"
IMAGE_SIZE="16G"
UUID="ee8d3593-59b1-480e-a3b6-4fefb17ee7d8"

ROOT_PASS="${ROOT_PASS:-1234}"
USER_PASS="${USER_PASS:-luser}"
USER_NAME="${USER_NAME:-luser}"

# --- 参数解析 ---
validate_args 1 3 $# '<kernel_version> [launcher:retroarch|steam|both] [output:sd|image]'
validate_root

KERNEL=$1
LAUNCHER=${2:-both}
OUTPUT_TYPE=${3:-sd}

TIMESTAMP=$(generate_timestamp)

case "$LAUNCHER" in
    retroarch|steam|both) ;;
    *) echo "错误: 无效的启动器 '$LAUNCHER' (可选: retroarch, steam, both)" >&2; exit 1 ;;
esac

case "$OUTPUT_TYPE" in
    sd|image) ;;
    *) echo "错误: 无效的输出类型 '$OUTPUT_TYPE' (可选: sd, image)" >&2; exit 1 ;;
esac

ROOTFS_IMG="sheng-gaming-os_${LAUNCHER}_${KERNEL}_${TIMESTAMP}.img"

echo ""
echo "=========================================="
echo " ROCKNIX+Armada 游戏系统构建"
echo " 启动器: $LAUNCHER | 内核: $KERNEL"
echo " 输出: $OUTPUT_TYPE | 镜像: $ROOTFS_IMG"
echo "=========================================="

preflight_checks 20480

# ===========================================================================
# Step 1: 创建根文件系统镜像
# ===========================================================================
echo "步骤 1/8: 创建根文件系统镜像..."
create_image "$IMAGE_SIZE" "$ROOTFS_IMG" "$UUID"
setup_chroot_mounts "$ROOTDIR"
trap_teardown "$ROOTDIR"

# ===========================================================================
# Step 2: 提取 Fedora 基础系统
# ===========================================================================
echo ""
echo "步骤 2/8: 提取 Fedora ${FEDORA_VERSION} 基础系统..."

OCI_TAR_XZ="fedora-${FEDORA_VERSION}-container.oci.tar.xz"
OCI_TAR="fedora-${FEDORA_VERSION}-container.oci.tar"

if [ ! -f "$OCI_TAR_XZ" ]; then
    echo "下载 Fedora ${FEDORA_VERSION} OCI 容器镜像..."
    wget -nv -O "$OCI_TAR_XZ" "$FEDORA_CONTAINER_URL" || {
        echo "尝试 TUNA 镜像..." >&2
        wget -nv -O "$OCI_TAR_XZ" \
            "https://mirrors.tuna.tsinghua.edu.cn/fedora/releases/${FEDORA_VERSION}/Container/aarch64/images/Fedora-Container-Base-Generic-${FEDORA_VERSION}-1.7.aarch64.oci.tar.xz" || {
            echo "错误: 下载 Fedora OCI 镜像失败" >&2
            exit 1
        }
    }
fi

echo "解压 OCI 镜像..."
xz -dkf "$OCI_TAR_XZ"

OCI_EXTRACT_DIR=$(mktemp -d)
tar -xf "$OCI_TAR" -C "$OCI_EXTRACT_DIR"

LAYER_FILES=$(find "$OCI_EXTRACT_DIR" -name "*.tar" -type f | sort)
if [ -z "$LAYER_FILES" ]; then
    echo "错误: OCI 镜像中没有找到层文件" >&2
    rm -rf "$OCI_EXTRACT_DIR"
    exit 1
fi

for layer in $LAYER_FILES; do
    echo "  提取层: $(basename "$layer")"
    tar -xf "$layer" -C "$ROOTDIR/" --keep-directory-symlink
done
rm -rf "$OCI_EXTRACT_DIR"
rm -f "$OCI_TAR"

setup_dns "$ROOTDIR" 8.8.8.8 1.1.1.1

# ===========================================================================
# Step 3: 安装基础系统包
# ===========================================================================
echo ""
echo "步骤 3/8: 安装基础系统包..."
chroot "$ROOTDIR" dnf -y install git gcc make kernel-headers
chroot "$ROOTDIR" dnf -y update --exclude=kernel-core
chroot "$ROOTDIR" dnf -y install --exclude=kernel-core \
    systemd sudo vim wget curl tar xz pciutils findutils \
    NetworkManager wpa_supplicant dialog qrtr \
    xdg-user-dirs dbus-x11 yad

# ===========================================================================
# Step 4: 内核注入
# ===========================================================================
echo ""
echo "步骤 4/8: 内核注入..."
if inject_deb_kernel "$ROOTDIR"; then
    KERNEL_MODULE_DIR=$(detect_kernel_module_dir "$ROOTDIR")
    if [ -n "$KERNEL_MODULE_DIR" ]; then
        echo "   内核版本: $KERNEL_MODULE_DIR"
        chroot "$ROOTDIR" dnf -y install dracut
        chroot "$ROOTDIR" dracut -N --kver "$KERNEL_MODULE_DIR" --force \
            "/boot/initramfs-${KERNEL_MODULE_DIR}.img"

        if [ -f "$ROOTDIR/boot/vmlinuz-$KERNEL_MODULE_DIR" ]; then
            cp "$ROOTDIR/boot/vmlinuz-$KERNEL_MODULE_DIR" "$ROOTDIR/boot/Image"
            cp "$ROOTDIR/boot/vmlinuz-$KERNEL_MODULE_DIR" "$ROOTDIR/boot/vmlinuz-linux"
        fi
    fi
else
    echo "错误: 未找到 .deb 内核包，无法生成可启动系统" >&2
    exit 1
fi

# 注入固件 tarball
tar_files=( *.tar.gz )
if [ ${#tar_files[@]} -gt 0 ] && [ -f "${tar_files[0]}" ]; then
    for tarball in "${tar_files[@]}"; do
        tar -xz --keep-directory-symlink -f "$tarball" -C "$ROOTDIR/"
    done
fi

# ===========================================================================
# Step 5: 游戏系统包安装
# ===========================================================================
echo ""
echo "步骤 5/8: 安装游戏系统包..."

enable_rpmfusion "$ROOTDIR" "$FEDORA_VERSION"

install_gaming_base "$ROOTDIR"

if [ "$LAUNCHER" = "retroarch" ] || [ "$LAUNCHER" = "both" ]; then
    echo ""
    echo "  >>> 安装 RetroArch + 核心..."
    install_retroarch "$ROOTDIR"
    install_emulationstation "$ROOTDIR"
fi

if [ "$LAUNCHER" = "steam" ] || [ "$LAUNCHER" = "both" ]; then
    echo ""
    echo "  >>> 安装 Steam + FEX..."
    install_steam_fex "$ROOTDIR"
fi

install_gamescope "$ROOTDIR"
install_mangohud "$ROOTDIR"
install_controller_support "$ROOTDIR"

# ===========================================================================
# Step 6: 系统配置
# ===========================================================================
echo ""
echo "步骤 6/8: 系统配置..."

setup_users "$ROOTDIR" "$ROOT_PASS" "$USER_NAME" "$USER_PASS" "wheel,audio,video,input"
echo "sheng-gaming" > "$ROOTDIR/etc/hostname"
echo "%wheel ALL=(ALL:ALL) NOPASSWD: ALL" > "$ROOTDIR/etc/sudoers.d/wheel"
chmod 440 "$ROOTDIR/etc/sudoers.d/wheel"

setup_getty_ttyMSM0 "$ROOTDIR"
chroot "$ROOTDIR" systemctl enable systemd-resolved NetworkManager
configure_touchscreen "$ROOTDIR"

# SELinux 禁用 (游戏系统兼容性)
mkdir -p "$ROOTDIR/etc/selinux"
echo "SELINUX=disabled" > "$ROOTDIR/etc/selinux/config"
echo "SELINUXTYPE=targeted" >> "$ROOTDIR/etc/selinux/config"

# 游戏会话配置
setup_gaming_session "$ROOTDIR" "$LAUNCHER"
setup_gaming_quirks "$ROOTDIR"

# WiFi 修复
fix_wifi_firmware "$ROOTDIR"

# QRTR 服务
setup_qrtr_service "$ROOTDIR"

# fstab (single boot mode for SD card)
generate_fstab "$ROOTDIR" "single"

# 启动到 GUI 模式
chroot "$ROOTDIR" systemctl set-default graphical.target

# 安装最简桌面环境 (Wayland)
echo "安装最简 Wayland 环境..."
chroot "$ROOTDIR" dnf -y install --exclude=kernel-core \
    weston \
    wayland-utils \
    mesa-libEGL \
    mesa-libGLES \
    mesa-libgbm \
    libdrm

# Weston 自动启动
mkdir -p "$ROOTDIR/etc/systemd/system/multi-user.target.wants"
cat > "$ROOTDIR/etc/systemd/system/gaming.target" <<'GTEOF'
[Unit]
Description=Gaming Target
Requires=multi-user.target
After=multi-user.target
AllowIsolate=yes

[Install]
WantedBy=multi-user.target
GTEOF

cat > "$ROOTDIR/etc/systemd/system/weston-gaming.service" <<'WGEOF'
[Unit]
Description=Weston Gaming Compositor
After=systemd-user-sessions.service
After=NetworkManager.service

[Service]
User=luser
Environment=XDG_RUNTIME_DIR=/run/user/1000
Environment=WAYLAND_DISPLAY=wayland-1
ExecStart=/usr/bin/weston --shell=kiosk --tty=1 --socket=wayland-1
ExecStartPost=/usr/local/bin/gaming-session both
Restart=always

[Install]
WantedBy=gaming.target
WGEOF

chroot "$ROOTDIR" systemctl set-default gaming.target
chroot "$ROOTDIR" systemctl enable weston-gaming

# ===========================================================================
# Step 7: 清理
# ===========================================================================
echo ""
echo "步骤 7/8: 清理..."
chroot "$ROOTDIR" dnf clean all

# 写入包列表
capture_package_list "$ROOTDIR" "$(pwd)/sheng-gaming-os_packages_${LAUNCHER}_${TIMESTAMP}.txt"

teardown_mounts "$ROOTDIR"

# ===========================================================================
# Step 8: 打包 / SD 卡镜像
# ===========================================================================
echo ""
echo "步骤 8/8: 打包输出..."

apply_fs_uuid "$UUID" "$ROOTFS_IMG"

if [ "$OUTPUT_TYPE" = "sd" ]; then
    SD_DIR="sheng-gaming-os_sd_${LAUNCHER}_${TIMESTAMP}"

    ABL_PATH="abl/sm8550/abl_signed-SM8550.elf"
    if [ ! -f "$ABL_PATH" ]; then
        ABL_PATH=""
    fi

    create_sd_card_image "$ROOTFS_IMG" "$SD_DIR" "$ABL_PATH"

    echo ""
    echo "=========================================="
    echo " SD 卡镜像构建完成！"
    echo " 镜像: ${SD_DIR}/xiaomi-sheng-gaming-os.img"
    echo " 刷写: ${SD_DIR}/flash_sd.sh"
    echo "=========================================="
else
    echo "正在转换为 Sparse 格式..."
    pack_sparse_image "$ROOTFS_IMG" "sheng-gaming-os_${LAUNCHER}_${KERNEL}_${TIMESTAMP}.7z"

    echo ""
    echo "=========================================="
    echo " Rootfs 镜像构建完成！"
    echo " 镜像: sheng-gaming-os_${LAUNCHER}_${KERNEL}_${TIMESTAMP}.7z"
    echo "=========================================="
fi

echo ""
echo "组件清单:"
echo "  - RetroArch + libretro 核心: $( [ "$LAUNCHER" = "retroarch" ] || [ "$LAUNCHER" = "both" ] && echo '已安装' || echo '未安装' )"
echo "  - EmulationStation DE: $( [ "$LAUNCHER" = "retroarch" ] || [ "$LAUNCHER" = "both" ] && echo '已安装' || echo '未安装' )"
echo "  - Steam + FEX: $( [ "$LAUNCHER" = "steam" ] || [ "$LAUNCHER" = "both" ] && echo '已安装' || echo '未安装' )"
echo "  - Gamescope: 已安装"
echo "  - MangoHud: 已安装"
echo "  - 手柄支持: 已安装"

trap - EXIT ERR INT TERM
echo "游戏系统构建完成！"
