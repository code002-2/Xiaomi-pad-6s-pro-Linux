#!/bin/bash
# =============================================================================
# rootfs-common.sh — Xiaomi Pad 6S Pro rootfs 构建公共库
# =============================================================================
# 所有 rootfs 构建脚本应 source 此文件，而非重复实现通用逻辑。
# 每个函数都接受显式参数，不依赖外部全局变量（除非另有说明）。
# =============================================================================

# ---------------------------------------------------------------------------
# create_image  — 创建 ext4 磁盘镜像并挂载
#   参数: <image_size> <image_path> <filesystem_uuid>
#   设置全局: ROOTDIR="rootdir"
# ---------------------------------------------------------------------------
create_image() {
    local image_size="$1" image_path="$2" fs_uuid="$3"
    ROOTDIR="rootdir"

    rm -rf "$ROOTDIR" || true
    truncate -s "$image_size" "$image_path"
    mkfs.ext4 -O ^metadata_csum "$image_path"
    mkdir -p "$ROOTDIR"
    mount -o loop "$image_path" "$ROOTDIR"
}

# ---------------------------------------------------------------------------
# setup_chroot_mounts  — 挂载 chroot 所需伪文件系统
#   参数: <rootdir>
# ---------------------------------------------------------------------------
setup_chroot_mounts() {
    local rootdir="$1"
    mount --bind /dev  "$rootdir/dev"
    mount --bind /dev/pts "$rootdir/dev/pts"
    mount -t proc proc "$rootdir/proc"
    mount -t sysfs sys  "$rootdir/sys"
}

# ---------------------------------------------------------------------------
# setup_dns  — 配置 DNS 解析器
#   参数: <rootdir> [nameserver ...]
# ---------------------------------------------------------------------------
setup_dns() {
    local rootdir="$1"
    shift
    rm -f "$rootdir/etc/resolv.conf"
    for ns in "$@"; do
        echo "nameserver $ns" >> "$rootdir/etc/resolv.conf"
    done
}

# ---------------------------------------------------------------------------
# configure_touchscreen  — 创建触摸屏校准 udev 规则
#   参数: <rootdir>
# ---------------------------------------------------------------------------
configure_touchscreen() {
    local rootdir="$1"
    mkdir -p "$rootdir/etc/udev/rules.d/"
    printf 'ENV{ID_INPUT_TOUCHSCREEN}=="1", ENV{LIBINPUT_CALIBRATION_MATRIX}="1 0 0 0 1 0 0 0 1"\n' \
        > "$rootdir/etc/udev/rules.d/99-touchscreen-sheng.rules"
}

# ---------------------------------------------------------------------------
# fix_wifi_firmware  — ath12k board-2.bin → board.bin 伪装
#   参数: <rootdir> [firmware_subdir]
#   默认 firmware_subdir: lib/firmware/ath12k/WCN7850/hw2.0
# ---------------------------------------------------------------------------
fix_wifi_firmware() {
    local rootdir="$1"
    local fw_subdir="${2:-lib/firmware/ath12k/WCN7850/hw2.0}"
    local fw_path="$rootdir/$fw_subdir"
    if [ -f "$fw_path/board-2.bin" ]; then
        cp "$fw_path/board-2.bin" "$fw_path/board.bin"
        echo "board.bin 伪装成功"
    fi
}

# ---------------------------------------------------------------------------
# setup_users  — 创建 root 和普通用户
#   参数: <rootdir> <root_pass> <user_name> <user_pass> [extra_groups]
# ---------------------------------------------------------------------------
setup_users() {
    local rootdir="$1" root_pass="$2" uname="$3" upass="$4" groups="${5:-sudo,audio,video,input}"

    chroot "$rootdir" bash -c "echo 'root:${root_pass}' | chpasswd"

    chroot "$rootdir" useradd -m -s /bin/bash "$uname" 2>/dev/null || true
    chroot "$rootdir" bash -c "echo '${uname}:${upass}' | chpasswd"
    chroot "$rootdir" usermod -aG "$groups" "$uname"
}

# ---------------------------------------------------------------------------
# setup_getty_ttyMSM0  — 启用 ttyMSM0 串口 getty
#   参数: <rootdir>
# ---------------------------------------------------------------------------
setup_getty_ttyMSM0() {
    local rootdir="$1"
    echo 'ttyMSM0' >> "$rootdir/etc/securetty"
    local link_src="/lib/systemd/system/getty@.service"
    if [ ! -f "$rootdir$link_src" ]; then
        link_src="/usr/lib/systemd/system/getty@.service"
    fi
    ln -sf "$link_src" "$rootdir/etc/systemd/system/getty.target.wants/getty@ttyMSM0.service"
}

# ---------------------------------------------------------------------------
# generate_fstab  — 根据启动模式生成 /etc/fstab
#   参数: <rootdir> <mode:dual|single>
# ---------------------------------------------------------------------------
generate_fstab() {
    local rootdir="$1" mode="$2"
    if [ "$mode" = "dual" ]; then
        echo "PARTLABEL=linux / ext4 defaults,noatime,errors=remount-ro 0 1" > "$rootdir/etc/fstab"
    else
        echo "PARTLABEL=userdata / ext4 defaults,noatime,errors=remount-ro 0 1" > "$rootdir/etc/fstab"
    fi
}

# ---------------------------------------------------------------------------
# setup_systemd_resolved_symlink  — 指向 systemd-resolved stub
#   参数: <rootdir>
# ---------------------------------------------------------------------------
setup_systemd_resolved_symlink() {
    local rootdir="$1"
    chroot "$rootdir" systemctl enable systemd-resolved 2>/dev/null || true
    ln -sf /run/systemd/resolve/stub-resolv.conf "$rootdir/etc/resolv.conf"
}

# ---------------------------------------------------------------------------
# teardown_mounts  — 卸载所有挂载并清理 rootdir
#   参数: <rootdir>
# ---------------------------------------------------------------------------
teardown_mounts() {
    local rootdir="$1"
    fuser -k -9 -m "$rootdir" 2>/dev/null || true
    sleep 2
    umount -l "$rootdir/dev/pts" 2>/dev/null || true
    umount -l "$rootdir/dev"  2>/dev/null || true
    umount -l "$rootdir/proc" 2>/dev/null || true
    umount -l "$rootdir/sys"   2>/dev/null || true
    umount -l "$rootdir"       2>/dev/null || true
    sleep 1
    rm -rf "$rootdir"
}

# ---------------------------------------------------------------------------
# pack_sparse_image  — 转换为 sparse 镜像并用 7z 极速压缩
#   参数: <image_path> <output_7z_path>
# ---------------------------------------------------------------------------
pack_sparse_image() {
    local image_path="$1" output_7z="$2"
    local sparse_img="sparse_${image_path}"
    img2simg "$image_path" "$sparse_img"
    7z a -mx=1 "$output_7z" "$sparse_img"
    rm -f "$image_path" "$sparse_img"
}

# ---------------------------------------------------------------------------
# apply_fs_uuid  — 设置文件系统 UUID
#   参数: <uuid> <image_path>
# ---------------------------------------------------------------------------
apply_fs_uuid() {
    local uuid="$1" image_path="$2"
    tune2fs -U "$uuid" "$image_path"
}

# ---------------------------------------------------------------------------
# trap_teardown  — 注册 EXIT/ERR/INT/TERM 信号处理器，确保卸载挂载
#   参数: <rootdir>
# ---------------------------------------------------------------------------
trap_teardown() {
    local rootdir="$1"
    trap 'teardown_mounts "$rootdir"' EXIT ERR INT TERM
}
