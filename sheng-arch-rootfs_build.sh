#!/bin/bash
set -e

# ==========================================
# ⚙️ 全局配置与参数检查
# ==========================================
IMAGE_SIZE="8G"
FILESYSTEM_UUID="ee8d3593-59b1-480e-a3b6-4fefb17ee7d8"
ALARM_MIRROR="http://mirror.archlinuxarm.org"

usage() {
    echo "用法: $0 <distro_name> <kernel_version> [desktop_environment]"
    echo "示例: $0 arch 7.1.0-rc6 kde"
    echo "      $0 arch 7.1.0-rc6 gnome"
    echo "      $0 arch 7.1.0-rc6 all"
    exit 1
}

if [ $# -lt 2 ] || [ $# -gt 3 ]; then usage; fi
if [ "$(id -u)" -ne 0 ]; then echo "❌ 必须使用 root 权限运行此脚本！"; exit 1; fi

DISTRO=$1
KERNEL=$2
TARGET_DE=${3:-gnome}
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

# 解析需要构建的桌面版本
DESKTOPS=()
if [ "$TARGET_DE" = "all" ]; then
    DESKTOPS=("gnome" "kde")
elif [[ "$TARGET_DE" =~ ^(gnome|kde)$ ]]; then
    DESKTOPS=("$TARGET_DE")
else
    echo "❌ 不支持的选项: $TARGET_DE (仅支持 gnome, kde, all)"
    exit 1
fi

# ==========================================
# 🛡️ 容错防线：无论发生什么，确保安全卸载
# ==========================================
cleanup_mounts() {
    echo "🧹 正在执行挂载点安全清理机制..."
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

# ==========================================
# 📦 核心函数区
# ==========================================
setup_base_env() {
    echo "⬇️ [阶段 1] 初始化磁盘与 Arch 基础系统 (${DE^^})..."
    rm -f "$ROOTFS_IMG"
    truncate -s $IMAGE_SIZE "$ROOTFS_IMG"
    mkfs.ext4 -O ^metadata_csum "$ROOTFS_IMG" 
    mkdir -p rootdir
    mount -o loop "$ROOTFS_IMG" rootdir

    # 如果同目录下没有基础包则下载，避免 all 模式重复下载
    if [ ! -f "ArchLinuxARM-aarch64-latest.tar.gz" ]; then
        wget -q http://os.archlinuxarm.org/os/ArchLinuxARM-aarch64-latest.tar.gz
    fi
    bsdtar -xpf ArchLinuxARM-aarch64-latest.tar.gz -C rootdir

    mount --bind /dev rootdir/dev
    mount --bind /dev/pts rootdir/dev/pts
    mount -t proc proc rootdir/proc
    mount -t sysfs sys rootdir/sys

    rm -f rootdir/etc/resolv.conf
    echo "nameserver 8.8.8.8" > rootdir/etc/resolv.conf
    echo "nameserver 1.1.1.1" >> rootdir/etc/resolv.conf
    echo "nameserver 208.67.222.222" >> rootdir/etc/resolv.conf
    
    echo "Server = $ALARM_MIRROR/\$arch/\$repo" > rootdir/etc/pacman.d/mirrorlist

    chroot rootdir pacman-key --init
    chroot rootdir pacman-key --populate archlinuxarm
    sed -i 's/^#DisableDownloadTimeout/DisableDownloadTimeout/' rootdir/etc/pacman.conf

    chroot rootdir pacman -Rdd --noconfirm linux-aarch64 linux-firmware || true
    chroot rootdir pacman -Syu --noconfirm base kmod glibc systemd sudo vim wget curl networkmanager wpa_supplicant dbus qrtr dialog
}

install_desktop_env() {
    echo "🖥️ [阶段 2] 正在安装 ${DE^^} 桌面环境..."
    if [ "$DE" = "gnome" ]; then
        chroot rootdir bash -c "pacman -Sgq gnome | grep -vE 'gnome-books|gnome-boxes' | pacman -S --noconfirm --needed - gdm gnome-tweaks"
        mkdir -p rootdir/etc/gdm
        printf "[daemon]\nAutomaticLoginEnable=True\nAutomaticLogin=luser\n" > rootdir/etc/gdm/custom.conf
        chroot rootdir systemctl enable gdm
    elif [ "$DE" = "kde" ]; then
        chroot rootdir pacman -S --noconfirm --needed plasma-meta sddm konsole dolphin ark gwenview
        mkdir -p rootdir/etc/sddm.conf.d
        printf "[Autologin]\nUser=luser\nSession=plasma\n" > rootdir/etc/sddm.conf.d/autologin.conf
        chroot rootdir systemctl enable sddm
    fi
    chroot rootdir systemctl set-default graphical.target
}

inject_kernel_and_firmware() {
    echo "🔨 [阶段 3] 注入本地内核与生成 Initramfs..."
    if ls *.deb 1> /dev/null 2>&1; then
        for pkg in *.deb; do
            echo "   -> 注入包: $pkg"
            dpkg-deb --fsys-tarfile "$pkg" | tar -x --keep-directory-symlink -C rootdir/
        done
        
        KERNEL_MODULE_DIR=$(ls -1t rootdir/usr/lib/modules/ | head -n 1)
        if [ -n "$KERNEL_MODULE_DIR" ]; then
            chroot rootdir /usr/bin/depmod -a "$KERNEL_MODULE_DIR" || true
            chroot rootdir pacman -S --noconfirm --needed mkinitcpio
            sed -i 's/autodetect //g' rootdir/etc/mkinitcpio.conf
            sed -i 's/autodetect//g' rootdir/etc/mkinitcpio.conf
            chroot rootdir mkinitcpio -k "$KERNEL_MODULE_DIR" -g "/boot/initramfs-linux.img"
            if [ -f "rootdir/boot/vmlinuz-$KERNEL_MODULE_DIR" ]; then
                cp "rootdir/boot/vmlinuz-$KERNEL_MODULE_DIR" "rootdir/boot/Image"
            fi
        fi
    else
        echo "⚠️ 警告：当前目录下未找到任何 .deb 内核包！"
    fi
}

apply_system_quirks() {
    echo "🩹 [阶段 4] 配置硬件补丁与账户权限..."
    echo 'en_US.UTF-8 UTF-8' > rootdir/etc/locale.gen
    chroot rootdir /usr/bin/locale-gen
    echo 'LANG=en_US.UTF-8' > rootdir/etc/locale.conf
    echo "arch-${DE}-sheng" > rootdir/etc/hostname

    chroot rootdir bash -c "echo 'root:1234' | chpasswd"
    chroot rootdir useradd -m -s /bin/bash luser || true
    chroot rootdir bash -c "echo 'luser:luser' | chpasswd"
    chroot rootdir usermod -aG wheel,audio,video,input luser
    echo "%wheel ALL=(ALL:ALL) NOPASSWD: ALL" > rootdir/etc/sudoers.d/wheel
    chmod 440 rootdir/etc/sudoers.d/wheel

ln -sf /usr/lib/systemd/system/getty@.service rootdir/etc/systemd/system/getty.target.wants/getty@ttyMSM0.service
    chroot rootdir systemctl enable systemd-resolved NetworkManager
    
    # ==========================================
    # 🚨 高通 QMI 通讯服务 (QRTR) 防弹自愈逻辑
    # ==========================================
    if chroot rootdir systemctl enable qrtr-ns 2>/dev/null; then
        echo "   ✅ qrtr-ns 服务已在系统中找到并启用！"
    else
        echo "   ⚠️ 未找到官方 qrtr-ns.service，正在为您手动生成守护进程..."
        cat << 'EOF' > rootdir/etc/systemd/system/qrtr-ns.service
[Unit]
Description=Qualcomm IPC Router Service (QRTR)
After=network.target

[Service]
ExecStart=/usr/bin/qrtr-ns -f
Restart=always

[Install]
WantedBy=multi-user.target
EOF
        chroot rootdir systemctl enable qrtr-ns
        echo "   ✅ 手动生成并启用 qrtr-ns 成功！"
    fi
    # ==========================================

    ln -sf /run/systemd/resolve/stub-resolv.conf rootdir/etc/resolv.conf

    mkdir -p rootdir/etc/udev/rules.d/
    printf 'ENV{ID_INPUT_TOUCHSCREEN}=="1", ENV{LIBINPUT_CALIBRATION_MATRIX}="1 0 0 0 1 0 0 0 1"\n' > rootdir/etc/udev/rules.d/99-touchscreen-sheng.rules
    
    FW_DIR="rootdir/usr/lib/firmware/ath12k/WCN7850/hw2.0"
    if [ -f "$FW_DIR/board-2.bin" ]; then cp "$FW_DIR/board-2.bin" "$FW_DIR/board.bin"; fi

    printf "PARTLABEL=linux / ext4 defaults,noatime,errors=remount-ro 0 1\n" > rootdir/etc/fstab
    chroot rootdir pacman -Scc --noconfirm
}

finalize_and_pack() {
    echo "🗜️ [阶段 5] 正在打包生成镜像..."
    cleanup_mounts 
    
    tune2fs -U $FILESYSTEM_UUID "$ROOTFS_IMG"
    SPARSE_IMG="sparse_${ROOTFS_IMG}"
    img2simg "$ROOTFS_IMG" "$SPARSE_IMG"
    7z a "${ROOTFS_IMG%.img}.7z" "$SPARSE_IMG"
    rm -f "$ROOTFS_IMG" "$SPARSE_IMG"
    
    echo "🎉 ${DE^^} 版本构建彻底圆满成功！产物: ${ROOTFS_IMG%.img}.7z"
}

# ==========================================
# 🚀 执行构建
# ==========================================
for DE in "${DESKTOPS[@]}"; do
    ROOTFS_IMG="${DISTRO}_${DE}_${TIMESTAMP}.img"
    echo ""
    echo "=========================================="
    echo "🌟 开始执行 -> 桌面: ${DE^^} | 目标: $ROOTFS_IMG"
    echo "=========================================="
    
    setup_base_env
    install_desktop_env
    inject_kernel_and_firmware
    apply_system_quirks
    finalize_and_pack
done

# 删除复用的缓存包
rm -f ArchLinuxARM-aarch64-latest.tar.gz
echo "✅ 所有指定的桌面环境构建任务已全部结束！"
