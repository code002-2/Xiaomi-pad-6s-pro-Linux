#!/bin/bash
set -euo pipefail

source "$(dirname "$0")/lib/rootfs-common.sh"

# --- Distro-specific configuration ---
IMAGE_SIZE="8G"
UUID="ee8d3593-59b1-480e-a3b6-4fefb17ee7d8"
FEDORA_VERSION="44"

# --- Password configuration ---
ROOT_PASS="${ROOT_PASS:-1234}"
USER_PASS="${USER_PASS:-luser}"
USER_NAME="${USER_NAME:-luser}"

# --- Argument parsing ---
if [ $# -lt 2 ] || [ $# -gt 5 ]; then
    echo "用法: $0 <distro_name> <kernel_version> [boot_mode] [desktop_env]"; echo "示例: $0 fedora 7.1 all gnome"
    exit 1
fi
if [ "$(id -u)" -ne 0 ]; then echo "请使用root权限运行"; exit 1; fi

DISTRO=$1
KERNEL=$2
TARGET_MODE=${3:-all}
TARGET_DE=${4:-gnome}
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
ROOTFS_IMG="fedora_desktop_${TIMESTAMP}.img"

echo "=========================================="
echo "开始构建纯净桌面版 Fedora ${FEDORA_VERSION} ARM RootFS"
echo "内核版本: $KERNEL"
echo "=========================================="

# Step 1: Create image
create_image "$IMAGE_SIZE" "$ROOTFS_IMG" "$UUID"

# Step 2: Docker extraction
echo "正在通过 Docker 提取 Fedora ${FEDORA_VERSION} 基础根文件系统..."
docker pull --platform linux/arm64 "fedora:${FEDORA_VERSION}"
docker create --name fedora-temp "fedora:${FEDORA_VERSION}"
docker export fedora-temp | tar -x -C "$ROOTDIR/"
docker rm fedora-temp

setup_chroot_mounts "$ROOTDIR"
setup_dns "$ROOTDIR" 8.8.8.8 1.1.1.1

# Step 3: Base packages
echo "正在安装编译工具..."
chroot "$ROOTDIR" dnf -y install git gcc make kernel-headers

echo "正在更新 Fedora 系统并安装基础组件..."
chroot "$ROOTDIR" dnf -y update --exclude=kernel-core
chroot "$ROOTDIR" dnf -y install --exclude=kernel-core \
    systemd sudo vim wget curl tar xz pciutils findutils \
    NetworkManager wpa_supplicant dialog qrtr

# Step 4: Desktop environment
echo "正在安装 ${TARGET_DE^^} 桌面环境..."
if [ "$TARGET_DE" = "kde" ]; then
    chroot "$ROOTDIR" dnf -y install @kde-desktop --exclude=kernel-core
    chroot "$ROOTDIR" dnf -y install sddm
else
    chroot "$ROOTDIR" dnf -y install @gnome-desktop --exclude=kernel-core
    chroot "$ROOTDIR" dnf -y install gdm
fi

# Step 5: Kernel injection
echo "正在扫描并注入本地内核与系统固件包..."
if ls *.deb 1> /dev/null 2>&1; then
    for pkg in *.deb; do
        echo "   -> 正在提取并覆盖注入 $pkg ..."
        dpkg-deb --fsys-tarfile "$pkg" | tar -x --keep-directory-symlink -C "$ROOTDIR/"
    done

    KERNEL_MODULE_DIR=$(ls -1t "$ROOTDIR/usr/lib/modules/" | head -n 1)
    if [ -n "$KERNEL_MODULE_DIR" ]; then
        echo "   动态识别到真实内核版本目录: $KERNEL_MODULE_DIR"
        chroot "$ROOTDIR" /usr/sbin/depmod -a "$KERNEL_MODULE_DIR" || true

        echo "   正在安装 dracut 并生成初始内存盘..."
        chroot "$ROOTDIR" dnf -y install dracut
        chroot "$ROOTDIR" dracut -N --kver "$KERNEL_MODULE_DIR" --force "/boot/initramfs-linux.img"

        if [ -f "$ROOTDIR/boot/vmlinuz-$KERNEL_MODULE_DIR" ]; then
            echo "   正在适配 Bootloader 内核命名..."
            cp "$ROOTDIR/boot/vmlinuz-$KERNEL_MODULE_DIR" "$ROOTDIR/boot/Image"
            cp "$ROOTDIR/boot/vmlinuz-$KERNEL_MODULE_DIR" "$ROOTDIR/boot/vmlinuz-linux"
        fi
    fi
fi

if ls *.tar.gz 1> /dev/null 2>&1; then
    for tarball in *.tar.gz; do
        tar -xz --keep-directory-symlink -f "$tarball" -C "$ROOTDIR/"
    done
fi

# Step 6: Users & hostname
chroot "$ROOTDIR" bash -c "echo 'root:${ROOT_PASS}' | chpasswd"
echo "fedora-sheng" > "$ROOTDIR/etc/hostname"
chroot "$ROOTDIR" useradd -m -s /bin/bash "$USER_NAME"
chroot "$ROOTDIR" bash -c "echo '${USER_NAME}:${USER_PASS}' | chpasswd"
chroot "$ROOTDIR" usermod -aG wheel,audio,video,input "$USER_NAME"
echo "%wheel ALL=(ALL:ALL) NOPASSWD: ALL" > "$ROOTDIR/etc/sudoers.d/wheel"
chmod 440 "$ROOTDIR/etc/sudoers.d/wheel"

# Step 7: Hardware quirks
echo "正在注入 Fedora 底层自愈补丁..."
setup_getty_ttyMSM0 "$ROOTDIR"
chroot "$ROOTDIR" systemctl enable systemd-resolved NetworkManager
configure_touchscreen "$ROOTDIR"

# SELinux disabled
mkdir -p "$ROOTDIR/etc/selinux"
echo "SELINUX=disabled" > "$ROOTDIR/etc/selinux/config"
echo "SELINUXTYPE=targeted" >> "$ROOTDIR/etc/selinux/config"

# Desktop autologin config
if [ "$TARGET_DE" = "kde" ]; then
    mkdir -p "$ROOTDIR/etc/sddm.conf.d"
    cat > "$ROOTDIR/etc/sddm.conf.d/autologin.conf" <<AUTHEOF
[Autologin]
User=$USER_NAME
Session=plasma
AUTHEOF
    chroot "$ROOTDIR" systemctl enable sddm
else
    mkdir -p "$ROOTDIR/etc/gdm"
    cat > "$ROOTDIR/etc/gdm/custom.conf" <<AUTHEOF2
[daemon]
AutomaticLoginEnable=True
AutomaticLogin=$USER_NAME
AUTHEOF2
    chroot "$ROOTDIR" systemctl enable gdm
fi
chroot "$ROOTDIR" systemctl set-default graphical.target

# WiFi fix
echo "正在预配置高通 WiFi 固件修复..."
FW_DIR="$ROOTDIR/usr/lib/firmware/ath12k/WCN7850/hw2.0"
if [ -f "$FW_DIR/board-2.bin" ]; then
    cp "$FW_DIR/board-2.bin" "$FW_DIR/board.bin"
    echo "   board.bin 伪装成功！"
fi

# QRTR force service
cat <<'EOF' > "$ROOTDIR/etc/systemd/system/qrtr-force.service"
[Unit]
Description=Qualcomm IPC Router Service (QRTR)
After=network.target

[Service]
ExecStart=/usr/bin/qrtr-ns -f
Restart=always

[Install]
WantedBy=multi-user.target
EOF
chroot "$ROOTDIR" systemctl enable qrtr-force.service

# Step 8: fstab & cleanup
generate_fstab "$ROOTDIR" "dual"
chroot "$ROOTDIR" dnf clean all
teardown_mounts "$ROOTDIR"

# Step 9: Pack
apply_fs_uuid "$UUID" "$ROOTFS_IMG"
echo "正在转换为 Sparse 格式加速刷机..."
pack_sparse_image "$ROOTFS_IMG" "fedora_desktop_${TIMESTAMP}.7z"

echo "🎉 Fedora ${FEDORA_VERSION} 版本构建圆满成功！"
