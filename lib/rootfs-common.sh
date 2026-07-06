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

    if [ -z "$image_size" ] || [ -z "$image_path" ] || [ -z "$fs_uuid" ]; then
        echo "错误: create_image 需要 <size> <path> <uuid> 三个参数" >&2
        return 1
    fi

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

    if [ ! -d "$rootdir" ]; then
        echo "错误: chroot 目录 '$rootdir' 不存在" >&2
        return 1
    fi

    mount --bind /dev  "$rootdir/dev" || { echo "错误: 挂载 /dev 失败" >&2; return 1; }
    mount --bind /dev/pts "$rootdir/dev/pts" || { echo "错误: 挂载 /dev/pts 失败" >&2; return 1; }
    mount -t proc proc "$rootdir/proc" || { echo "错误: 挂载 /proc 失败" >&2; return 1; }
    mount -t sysfs sys  "$rootdir/sys" || { echo "错误: 挂载 /sys 失败" >&2; return 1; }
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
    else
        echo "警告: 未找到 $fw_path/board-2.bin，跳过 WiFi 固件修复" >&2
    fi
}

# ---------------------------------------------------------------------------
# setup_users  — 创建 root 和普通用户
#   参数: <rootdir> <root_pass> <user_name> <user_pass> [extra_groups]
# ---------------------------------------------------------------------------
setup_users() {
    local rootdir="$1" root_pass="$2" uname="$3" upass="$4" groups="${5:-sudo,audio,video,input}"

    if [ -z "$root_pass" ] || [ -z "$uname" ] || [ -z "$upass" ]; then
        echo "错误: setup_users 需要 <rootdir> <root_pass> <user_name> <user_pass> [groups]" >&2
        return 1
    fi

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
# setup_autologin  — 配置显示管理器自动登录
#   参数: <rootdir> <desktop_env:gnome|kde|xfce> <username>
# ---------------------------------------------------------------------------
setup_autologin() {
    local rootdir="$1" desktop="$2" username="$3"

    case "$desktop" in
        gnome)
            mkdir -p "$rootdir/etc/gdm3"
            cat > "$rootdir/etc/gdm3/daemon.conf" <<EOF
[daemon]
AutomaticLoginEnable=true
AutomaticLogin=${username}
EOF
            chroot "$rootdir" systemctl enable gdm3 2>/dev/null || true
            ;;
        kde)
            mkdir -p "$rootdir/etc/sddm.conf.d"
            cat > "$rootdir/etc/sddm.conf.d/autologin.conf" <<EOF
[Autologin]
User=${username}
Session=plasma
EOF
            chroot "$rootdir" systemctl enable sddm 2>/dev/null || true
            ;;
        xfce)
            mkdir -p "$rootdir/etc/lightdm/lightdm.conf.d"
            cat > "$rootdir/etc/lightdm/lightdm.conf.d/autologin.conf" <<EOF
[Seat:*]
autologin-user=${username}
autologin-user-timeout=0
EOF
            chroot "$rootdir" systemctl enable lightdm 2>/dev/null || true
            ;;
        *)
            echo "警告: 未知的桌面环境 '$desktop'，跳过自动登录配置" >&2
            return 0
            ;;
    esac
}

# ---------------------------------------------------------------------------
# detect_kernel_module_dir  — 检测 chroot 中的内核模块目录
#   参数: <rootdir>
#   返回: 模块目录名（如 6.1.0 或 usr/lib/modules/6.1.0）
# ---------------------------------------------------------------------------
detect_kernel_module_dir() {
    local rootdir="$1"
    # Try /usr/lib/modules first (usr-merged systems: Arch, Fedora, modern Debian)
    local moddir
    moddir=$(ls -1 "$rootdir/usr/lib/modules/" 2>/dev/null | sort -V | tail -n 1)
    if [ -n "$moddir" ]; then
        echo "$moddir"
        return 0
    fi
    # Fall back to /lib/modules (older Debian/Ubuntu)
    moddir=$(ls -1 "$rootdir/lib/modules/" 2>/dev/null | sort -V | tail -n 1)
    if [ -n "$moddir" ]; then
        echo "$moddir"
        return 0
    fi
    return 1
}

# ---------------------------------------------------------------------------
# setup_qrtr_service  — 统一 QRTR 服务创建
#   参数: <rootdir>
#   行为: 优先启用系统自带的 qrtr-ns.service，若不存在则创建内联版本
# ---------------------------------------------------------------------------
setup_qrtr_service() {
    local rootdir="$1"
    if chroot "$rootdir" systemctl enable qrtr-ns 2>/dev/null; then
        echo "   qrtr-ns 服务已在系统中找到并启用！"
    else
        echo "   未找到官方 qrtr-ns.service，正在创建守护进程..."
        cat > "$rootdir/etc/systemd/system/qrtr-ns.service" <<'EOF'
[Unit]
Description=Qualcomm IPC Router Service (QRTR)
After=network.target

[Service]
ExecStart=/usr/bin/qrtr-ns -f
Restart=always

[Install]
WantedBy=multi-user.target
EOF
        chroot "$rootdir" systemctl enable qrtr-ns
    fi
}

# ---------------------------------------------------------------------------
# setup_systemd_resolved_symlink  — 指向 systemd-resolved stub
#   参数: <rootdir>
#   注意: 调用此函数后不应再调用 setup_dns()，两者冲突
# ---------------------------------------------------------------------------
setup_systemd_resolved_symlink() {
    local rootdir="$1"
    chroot "$rootdir" systemctl enable systemd-resolved 2>/dev/null || true
    ln -sf /run/systemd/resolve/stub-resolv.conf "$rootdir/etc/resolv.conf"
}

# ---------------------------------------------------------------------------
# preflight_checks  — 预飞检查：工具可用性、磁盘空间、权限
#   参数: <required_min_space_mb> [extra_tool ...]
#   用法: preflight_checks 10240              # 基础工具
#         preflight_checks 10240 debootstrap   # 额外需求
# ---------------------------------------------------------------------------
preflight_checks() {
    local min_space_mb="${1:-10240}"
    shift || true

    # 检查 root 权限
    if [ "$(id -u)" -ne 0 ]; then
        echo "错误: 此脚本必须以 root 权限运行" >&2
        return 1
    fi

    # 通用必要工具（所有发行版都需要）
    local tools="truncate mkfs.ext4 img2simg 7z dpkg-deb tune2fs fuser"
    # 追加发行版特定的工具检查
    for tool in "$@"; do
        tools="$tools $tool"
    done

    for tool in $tools; do
        if ! command -v "$tool" &>/dev/null; then
            echo "错误: 缺少必要工具 '$tool'" >&2
            return 1
        fi
    done

    # 检查磁盘空间
    local avail_kb
    avail_kb=$(df --output=avail "$PWD" 2>/dev/null | tail -1)
    if [ -n "$avail_kb" ]; then
        local avail_mb=$((avail_kb / 1024))
        if [ "$avail_mb" -lt "$min_space_mb" ]; then
            echo "错误: 磁盘空间不足（需要 ${min_space_mb}MB，可用 ${avail_mb}MB）" >&2
            return 1
        fi
    fi
}

# ---------------------------------------------------------------------------
# teardown_mounts  — 卸载所有挂载并清理 rootdir
#   参数: <rootdir>
# ---------------------------------------------------------------------------
teardown_mounts() {
    local rootdir="$1"
    if [ ! -d "$rootdir" ]; then
        return 0
    fi
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

    if [ ! -f "$image_path" ]; then
        echo "错误: 镜像文件 '$image_path' 不存在" >&2
        return 1
    fi

    local sparse_img="sparse_${image_path}"
    if ! img2simg "$image_path" "$sparse_img"; then
        echo "错误: img2simg 转换失败" >&2
        return 1
    fi
    if ! 7z a -mx=1 "$output_7z" "$sparse_img"; then
        echo "错误: 7z 压缩失败" >&2
        rm -f "$sparse_img"
        return 1
    fi
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
#   注意: 调用方应在整个构建完成后清除 trap，而非逐次清除
# ---------------------------------------------------------------------------
trap_teardown() {
    local rootdir="$1"
    TEARDOWN_ROOTDIR="$rootdir"
    # Register EXIT handler for cleanup only (no exit 1 — normal exit succeeds).
    # ERR/INT/TERM handlers clean up AND exit with failure.
    trap '_teardown_handler cleanup' EXIT
    trap '_teardown_handler fatal' ERR INT TERM
}

# Internal handler that runs cleanup, optionally with a failing exit.
#   _teardown_handler cleanup  — run teardown, then return (normal exit proceeds)
#   _teardown_handler fatal    — run teardown, then exit 1
_teardown_handler() {
    local mode="${1:-fatal}"
    if [ -n "${TEARDOWN_ROOTDIR:-}" ]; then
        teardown_mounts "$TEARDOWN_ROOTDIR"
        TEARDOWN_ROOTDIR=""
    fi
    if [ "$mode" = "fatal" ]; then
        exit 1
    fi
}

# ---------------------------------------------------------------------------
# parse_boot_modes  -- 解析启动模式参数
#   参数: <target_mode> (all, dual, single)
#   返回: 以换行符分隔的模式列表
#   用法: mapfile -t BOOTMODES < <(parse_boot_modes "$TARGET_MODE")
# ---------------------------------------------------------------------------
parse_boot_modes() {
    local target="$1"
    case "${target:-all}" in
        all)    printf '%s\n' "dual" "single" ;;
        dual)   echo "dual" ;;
        single) echo "single" ;;
        *)      echo "Error: unsupported boot mode: $target (use: dual, single, all)" >&2
                return 1 ;;
    esac
}

# ---------------------------------------------------------------------------
# parse_desktops  -- 解析桌面环境参数
#   参数: <target_de> (all, gnome, kde, xfce)
#   返回: 以换行符分隔的桌面环境列表
# ---------------------------------------------------------------------------
parse_desktops() {
    local target="$1"
    case "${target:-all}" in
        all)    printf '%s\n' "gnome" "kde" ;;
        gnome)  echo "gnome" ;;
        kde)    echo "kde" ;;
        xfce)   echo "xfce" ;;
        *)      echo "Error: unsupported desktop: $target (use: gnome, kde, xfce, all)" >&2
                return 1 ;;
    esac
}

# ---------------------------------------------------------------------------
# generate_timestamp  -- 生成构建时间戳 YYYYMMDD_HHMMSS
# ---------------------------------------------------------------------------
generate_timestamp() {
    date +"%Y%m%d_%H%M%S"
}

# ---------------------------------------------------------------------------
# validate_root  -- 检查 root 权限，失败则退出
# ---------------------------------------------------------------------------
validate_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo "Error: must run as root" >&2
        exit 1
    fi
}

# ---------------------------------------------------------------------------
# validate_args  -- 通用参数数量校验
#   参数: <min> <max> <actual_count> <usage_msg>
# ---------------------------------------------------------------------------
validate_args() {
    local min="$1" max="$2" actual="$3" usage="$4"
    if [ "$actual" -lt "$min" ] || [ "$actual" -gt "$max" ]; then
        echo "Usage: $usage" >&2
        exit 1
    fi
}

# ---------------------------------------------------------------------------
# inject_deb_kernel  -- 将 .deb 内核包注入到 chroot
#   参数: <rootdir> [deb_pattern]
#   默认 deb_pattern: ./*.deb
#   返回: 0 成功，1 未找到 .deb
# ---------------------------------------------------------------------------
inject_deb_kernel() {
    local rootdir="$1" pattern="${2:-./*.deb}"
    local deb_files=( $pattern )
    if [ ${#deb_files[@]} -eq 0 ] || [ ! -f "${deb_files[0]}" ]; then
        echo "Error: no .deb kernel packages matching '$pattern' found" >&2
        return 1
    fi
    for pkg in "${deb_files[@]}"; do
        echo "  -> injecting: $pkg"
        dpkg-deb --fsys-tarfile "$pkg" | tar -x --keep-directory-symlink -C "$rootdir/"
    done

    local mod_dir
    mod_dir=$(detect_kernel_module_dir "$rootdir")
    if [ -n "$mod_dir" ]; then
        echo "  detected kernel module dir: $mod_dir"
        chroot "$rootdir" depmod -a "$mod_dir" 2>/dev/null || true
    fi
}

# ---------------------------------------------------------------------------
# capture_package_list  -- 在 chroot 中列出已安装包并写入文件
#   参数: <rootdir> <output_path>
# ---------------------------------------------------------------------------
capture_package_list() {
    local rootdir="$1" output="$2"
    if [ -x "$rootdir/usr/bin/dpkg" ]; then
        chroot "$rootdir" dpkg -l > "$output" 2>/dev/null
    elif [ -x "$rootdir/usr/bin/pacman" ]; then
        chroot "$rootdir" pacman -Q > "$output" 2>/dev/null
    elif [ -x "$rootdir/usr/bin/rpm" ]; then
        chroot "$rootdir" rpm -qa > "$output" 2>/dev/null
    fi
}

# ---------------------------------------------------------------------------
# download_firmware  -- 下载并提取 linux-firmware-sheng
#   参数: <output_dir> (默认: firmware-xiaomi-sheng/usr/lib)
# ---------------------------------------------------------------------------
download_firmware() {
    local outdir="${1:-firmware-xiaomi-sheng/usr/lib}"
    mkdir -p "$outdir"
    local tmpdir
    tmpdir=$(mktemp -d)
    git clone --depth 1 --single-branch https://github.com/lzxcr/linux-firmware-sheng.git "$tmpdir/fw" 2>/dev/null || {
        echo "Warning: firmware repo clone failed" >&2
        rm -rf "$tmpdir"
        return 1
    }
    if [ -d "$tmpdir/fw/lib" ]; then
        cp -r "$tmpdir/fw/lib"/* "$outdir/"
    else
        cp -r "$tmpdir/fw"/* "$outdir/" 2>/dev/null || true
    fi
    rm -rf "$tmpdir"
    echo "Firmware extracted to $outdir"
}

# ---------------------------------------------------------------------------
# download_alsa_ucm  -- 下载并提取 ALSA UCM2 配置
#   参数: <output_dir> (默认: alsa-xiaomi-sheng/usr/share/alsa/ucm2)
# ---------------------------------------------------------------------------
download_alsa_ucm() {
    local outdir="${1:-alsa-xiaomi-sheng/usr/share/alsa/ucm2}"
    mkdir -p "$outdir"
    local tmpdir
    tmpdir=$(mktemp -d)
    git clone --depth 1 --single-branch https://github.com/map220v/alsa-ucm-conf.git "$tmpdir/alsa" 2>/dev/null || {
        echo "Warning: ALSA UCM repo clone failed" >&2
        rm -rf "$tmpdir"
        return 1
    }
    if [ -d "$tmpdir/alsa/ucm2" ]; then
        cp -r "$tmpdir/alsa/ucm2"/* "$outdir/"
    else
        cp -r "$tmpdir/alsa"/* "$outdir/" 2>/dev/null || true
    fi
    rm -rf "$tmpdir"
    echo "ALSA UCM2 extracted to $outdir"
}

# ---------------------------------------------------------------------------
# usr_merge  -- 将 /lib 合并到 /usr/lib（UsrMerge 过渡）
#   参数: <pkg_dirs...>
# ---------------------------------------------------------------------------
usr_merge() {
    local rc=0
    for pkg in "$@"; do
        if [ -d "$pkg/lib" ]; then
            echo "UsrMerge: merging $pkg/lib -> $pkg/usr/lib..."
            mkdir -p "$pkg/usr/lib"
            if ! cp -r "$pkg/lib"/* "$pkg/usr/lib/" 2>/dev/null; then
                echo "Error: usr_merge $pkg/lib failed" >&2
                rc=1
            else
                rm -rf "$pkg/lib"
            fi
        fi
    done
    return "$rc"
}
