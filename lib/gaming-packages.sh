#!/bin/bash
# =============================================================================
# gaming-packages.sh — ROCKNIX+Armada 混合游戏系统安装函数库
# =============================================================================

# ---------------------------------------------------------------------------
# enable_rpmfusion  — 在 Fedora chroot 中启用 RPM Fusion
#   参数: <rootdir> <fedora_version>
# ---------------------------------------------------------------------------
enable_rpmfusion() {
    local rootdir="$1" fedora_ver="$2"

    chroot "$rootdir" dnf -y install \
        "https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-${fedora_ver}.noarch.rpm" \
        "https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-${fedora_ver}.noarch.rpm"
}

# ---------------------------------------------------------------------------
# install_retroarch  — 安装 RetroArch + 核心库
#   参数: <rootdir>
#   安装: retroarch, libretro 核心, vulkan, mesa 驱动
# ---------------------------------------------------------------------------
install_retroarch() {
    local rootdir="$1"

    echo "正在安装 RetroArch 和 libretro 核心..."
    chroot "$rootdir" dnf -y install \
        retroarch \
        libretro-beetle-pce-fast \
        libretro-beetle-psx \
        libretro-beetle-psx-hw \
        libretro-beetle-saturn \
        libretro-beetle-supergrafx \
        libretro-blastem \
        libretro-bsnes \
        libretro-desmume \
        libretro-dolphin \
        libretro-fceumm \
        libretro-flycast \
        libretro-gambatte \
        libretro-genesis-plus-gx \
        libretro-mgba \
        libretro-mupen64plus-next \
        libretro-nestopia \
        libretro-pcsx2 \
        libretro-picodrive \
        libretro-ppsspp \
        libretro-snes9x \
        libretro-stella \
        libretro-vba-next \
        libretro-yabause \
        retroarch-assets \
        retroarch-database \
        libretro-shaders-glsl \
        libretro-shaders-slang

    mkdir -p "$rootdir/usr/share/libretro/info"
    mkdir -p "$rootdir/usr/lib64/libretro"

    chroot "$rootdir" dnf -y install \
        mesa-vulkan-drivers \
        mesa-dri-drivers \
        vulkan-loader

    echo "RetroArch 安装完成"
}

# ---------------------------------------------------------------------------
# install_emulationstation  — 安装 EmulationStation Desktop Edition
#   参数: <rootdir>
#   安装: ES-DE 来自官方 GitHub release
# ---------------------------------------------------------------------------
install_emulationstation() {
    local rootdir="$1"
    local es_version="3.1.6"
    local es_url="https://gitlab.com/es-de/emulationstation-de/-/releases/v${es_version}/downloads/EmulationStation-DE-x64_${es_version}.AppImage"

    echo "正在安装 EmulationStation Desktop Edition ${es_version}..."
    chroot "$rootdir" dnf -y install fuse-libs

    wget -nv -O "$rootdir/usr/local/bin/EmulationStation.AppImage" "$es_url" || {
        echo "警告: ES-DE 下载失败，尝试备用源..." >&2
        es_url="https://gitlab.com/es-de/emulationstation-de/-/releases/v3.1.5/downloads/EmulationStation-DE-x64_3.1.5.AppImage"
        wget -nv -O "$rootdir/usr/local/bin/EmulationStation.AppImage" "$es_url" || {
            echo "警告: ES-DE 下载失败，跳过安装" >&2
            return 1
        }
    }
    chmod +x "$rootdir/usr/local/bin/EmulationStation.AppImage"

    mkdir -p "$rootdir/home/luser/ES-DE"
    mkdir -p "$rootdir/home/luser/ES-DE/roms"
    mkdir -p "$rootdir/home/luser/ES-DE/downloaded_media"
    mkdir -p "$rootdir/home/luser/ES-DE/gamelists"

    cat > "$rootdir/home/luser/ES-DE/es_settings.xml" <<'ESEOF'
<?xml version="1.0"?>
<settings>
    <string name="ThemeSet" value="linear-es-de" />
    <string name="UIMode" value="full" />
    <string name="UIMode_passkey" value="uuddlrlrba" />
    <bool name="FullscreenMode" value="true" />
    <bool name="RunInBackground" value="true" />
    <string name="ROMDirectory" value="~/ES-DE/roms" />
</settings>
ESEOF

    chroot "$rootdir" chown -R luser:luser /home/luser/ES-DE

    echo "EmulationStation DE 安装完成"
}

# ---------------------------------------------------------------------------
# install_gamescope  — 安装 Gamescope 微合成器
#   参数: <rootdir>
# ---------------------------------------------------------------------------
install_gamescope() {
    local rootdir="$1"

    echo "正在安装 Gamescope..."
    chroot "$rootdir" dnf -y install gamescope || {
        echo "警告: 从仓库安装 gamescope 失败，从 COPR 尝试..." >&2
        chroot "$rootdir" dnf -y copr enable keszybz/gamescope
        chroot "$rootdir" dnf -y install gamescope || {
            echo "警告: gamescope 安装失败，跳过" >&2
            return 1
        }
    }
    echo "Gamescope 安装完成"
}

# ---------------------------------------------------------------------------
# install_steam_fex  — 安装 Steam + FEX x86_64 模拟
#   参数: <rootdir>
#   注意: Steam 需要 FEX 来运行 x86_64 游戏在 aarch64 上
# ---------------------------------------------------------------------------
install_steam_fex() {
    local rootdir="$1"

    echo "正在安装 Steam + FEX (aarch64 x86_64 游戏支持)..."

    chroot "$rootdir" dnf -y install \
        steam \
        steam-devices

    echo "正在安装 FEX-Emu..."
    chroot "$rootdir" dnf -y copr enable virtudude/armada
    chroot "$rootdir" dnf -y install FEX || {
        echo "警告: FEX 安装失败，尝试手动安装..." >&2
        local fex_url="https://github.com/FEX-Emu/FEX/releases/download/FEX-2501/FEX-2501-aarch64.tar.gz"
        wget -nv -O /tmp/FEX.tar.gz "$fex_url" || return 1
        tar -xzf /tmp/FEX.tar.gz -C "$rootdir/usr/local/"
        rm -f /tmp/FEX.tar.gz
    }

    cat > "$rootdir/usr/local/bin/steam-fex" <<'SESOF'
#!/bin/bash
export FEX_ROOTFS=/var/lib/FEX/rootfs
export STEAM_RUNTIME=1
export STEAM_FRAME_FORCE_CLOSE=1
export SDL_VIDEO_DRIVER=wayland

FEXBash steam "$@"
SESOF
    chmod +x "$rootdir/usr/local/bin/steam-fex"

    mkdir -p "$rootdir/home/luser/.local/share/Steam"
    chroot "$rootdir" chown -R luser:luser /home/luser/.local/share/Steam

    echo "Steam + FEX 安装完成"
}

# ---------------------------------------------------------------------------
# install_gaming_base  — 安装游戏系统基础依赖
#   参数: <rootdir>
# ---------------------------------------------------------------------------
install_gaming_base() {
    local rootdir="$1"

    echo "正在安装游戏系统基础依赖..."
    chroot "$rootdir" dnf -y install \
        alsa-lib \
        alsa-plugins-pulseaudio \
        pulseaudio \
        pipewire \
        pipewire-alsa \
        pipewire-pulseaudio \
        pipewire-jack-audio-connection-kit \
        wireplumber \
        libevdev \
        libinput \
        libdrm \
        libglvnd \
        libglvnd-egl \
        libglvnd-gles \
        libxkbcommon \
        libxcb \
        libX11 \
        libXau \
        libXdmcp \
        libXext \
        libXcursor \
        libXfixes \
        libXi \
        libXrandr \
        libXrender \
        libXScrnSaver \
        fontconfig \
        freetype \
        libpng \
        zlib \
        bzip2 \
        xz

    chroot "$rootdir" systemctl enable --global pipewire 2>/dev/null || true
    chroot "$rootdir" systemctl enable --global wireplumber 2>/dev/null || true

    echo "游戏系统基础依赖安装完成"
}

# ---------------------------------------------------------------------------
# install_mangohud  — 安装 MangoHud 性能监视覆盖层
#   参数: <rootdir>
# ---------------------------------------------------------------------------
install_mangohud() {
    local rootdir="$1"

    echo "正在安装 MangoHud..."
    chroot "$rootdir" dnf -y install mangohud || {
        echo "警告: mangohud 安装失败，跳过" >&2
        return 1
    }
    echo "MangoHud 安装完成"
}

# ---------------------------------------------------------------------------
# install_controller_support  — 安装手柄/控制器支持
#   参数: <rootdir>
# ---------------------------------------------------------------------------
install_controller_support() {
    local rootdir="$1"

    echo "正在安装手柄支持..."
    chroot "$rootdir" dnf -y install \
        SDL2 \
        SDL2-devel \
        libusb \
        joystick-support \
        steam-devices

    cat > "$rootdir/etc/udev/rules.d/99-gamepad.rules" <<'GEOF'
# Generic gamepad support
SUBSYSTEM=="input", ATTRS{name}=="*Gamepad*", MODE="0666", ENV{ID_INPUT_JOYSTICK}="1"
SUBSYSTEM=="input", ATTRS{name}=="*Xbox*", MODE="0666", ENV{ID_INPUT_JOYSTICK}="1"
SUBSYSTEM=="input", ATTRS{name}=="*PlayStation*", MODE="0666", ENV{ID_INPUT_JOYSTICK}="1"
SUBSYSTEM=="input", ATTRS{name}=="*DualSense*", MODE="0666", ENV{ID_INPUT_JOYSTICK}="1"
SUBSYSTEM=="input", ATTRS{name}=="*DualShock*", MODE="0666", ENV{ID_INPUT_JOYSTICK}="1"
SUBSYSTEM=="input", ATTRS{name}=="*Nintendo*", MODE="0666", ENV{ID_INPUT_JOYSTICK}="1"
SUBSYSTEM=="input", ATTRS{name}=="*Controller*", MODE="0666", ENV{ID_INPUT_JOYSTICK}="1"
SUBSYSTEM=="input", ATTRS{name}=="*8BitDo*", MODE="0666", ENV{ID_INPUT_JOYSTICK}="1"
GEOF

    echo "手柄支持配置完成"
}

# ---------------------------------------------------------------------------
# setup_gaming_session  — 配置游戏会话自动启动
#   参数: <rootdir> <launcher:retroarch|steam|both>
# ---------------------------------------------------------------------------
setup_gaming_session() {
    local rootdir="$1" launcher="${2:-both}"

    echo "正在配置游戏会话 (launcher=$launcher)..."

    cat > "$rootdir/usr/local/bin/gaming-session" <<'GAMEOF'
#!/bin/bash
# ROCKNIX+Armada Hybrid Gaming Session
# Launcher selection: RetroArch/ES-DE or Steam Big Picture

GAMING_LOG="/home/luser/gaming-session.log"
LAUNCHER_TYPE="${1:-both}"
DISPLAY_BACKEND="${DISPLAY_BACKEND:-wayland}"

export XDG_RUNTIME_DIR=/run/user/1000
export SDL_VIDEO_DRIVER=wayland
export QT_QPA_PLATFORM=wayland
export GDK_BACKEND=wayland
export MOZ_ENABLE_WAYLAND=1

# Wait for display
for i in $(seq 1 30); do
    if [ -e /dev/dri/card0 ]; then
        break
    fi
    sleep 1
done

start_es_de() {
    echo "[$(date)] 启动 EmulationStation DE..." >> "$GAMING_LOG"
    gamescope -e -f -- /usr/local/bin/EmulationStation.AppImage
}

start_steam_bpm() {
    echo "[$(date)] 启动 Steam Big Picture (via FEX)..." >> "$GAMING_LOG"
    gamescope -e -f -- /usr/local/bin/steam-fex -tenfoot -fulldesktopres -gamepadui
}

start_launcher_menu() {
    while true; do
        CHOICE=$(yad --title="Gaming OS" --text="选择游戏模式" \
            --button="Emulators (ES-DE):0" \
            --button="PC Games (Steam):2" \
            --button="Exit to Shell:4" \
            --center --on-top --width=600 --height=300)

        case $? in
            0) start_es_de ;;
            2) start_steam_bpm ;;
            4) exit 0 ;;
            *) start_es_de ;;
        esac
    done
}

case "$LAUNCHER_TYPE" in
    retroarch|esde|es|emulationstation)
        start_es_de
        ;;
    steam|fex|pc)
        start_steam_bpm
        ;;
    both|all)
        start_launcher_menu
        ;;
    *)
        start_launcher_menu
        ;;
esac
GAMEOF
    chmod +x "$rootdir/usr/local/bin/gaming-session"

    local autostart_dir="$rootdir/home/luser/.config/autostart"
    mkdir -p "$autostart_dir"

    cat > "$autostart_dir/gaming-session.desktop" <<'AEOF'
[Desktop Entry]
Type=Application
Name=Gaming Session
Comment=ROCKNIX+Armada Gaming Session
Exec=/usr/local/bin/gaming-session both
X-GNOME-Autostart-enabled=true
NoDisplay=true
AEOF

    cat > "$rootdir/etc/profile.d/gaming-env.sh" <<'ENVEOF'
# Gaming environment variables
export SDL_VIDEO_DRIVER=wayland
export QT_QPA_PLATFORM=wayland
export GDK_BACKEND=wayland
export MOZ_ENABLE_WAYLAND=1
export GALLIUM_HUD="fps,cpu,gpu"
ENVEOF

    chroot "$rootdir" chown -R luser:luser /home/luser/.config
    chroot "$rootdir" chown luser:luser /home/luser/gaming-session.log 2>/dev/null || true

    echo "游戏会话配置完成"
}

# ---------------------------------------------------------------------------
# create_sd_card_image  — 创建 SD 卡刷写镜像
#   参数: <rootfs_img> <output_dir> [abl_path] [kernel_img]
#   生成: xiaomi-sheng-gaming-os.img + 辅助脚本
#   结构:
#     /boot/           — ABL + DTBO
#     /LINUX.IMG       — 内核 Image（含 dtb）
#     /initrd.img      — initramfs
#     /rootfs.ext4     — 根文件系统
# ---------------------------------------------------------------------------
create_sd_card_image() {
    local rootfs_img="$1" output_dir="${2:-sd-image}" abl_path="${3:-}" kernel_img="${4:-}"
    local sd_size="32G"

    echo "正在创建 SD 卡刷写镜像..."

    mkdir -p "$output_dir"

    local sd_img="$output_dir/xiaomi-sheng-gaming-os.img"
    local tmp_mnt=$(mktemp -d)
    local rootfs_mnt=$(mktemp -d)

    truncate -s "$sd_size" "$sd_img"

    cat > "$tmp_mnt/sfdisk.cmd" <<EOF
label: gpt
start=2048, size=524288, type=C12A7328-F81F-11D2-BA4B-00A0C93EC93B, name="EFI"
start=526336, size=1048576, type=0FC63DAF-8483-4772-8E79-3D69D8477DE4, name="BOOT"
start=1574912, type=0FC63DAF-8483-4772-8E79-3D69D8477DE4, name="ROOTFS"
EOF

    sfdisk "$sd_img" < "$tmp_mnt/sfdisk.cmd"

    local loop_dev
    loop_dev=$(losetup --show -f -P "$sd_img")
    sleep 1

    mkfs.vfat -F 32 -n EFI "${loop_dev}p1" 2>/dev/null || true
    mkfs.ext4 -L BOOT "${loop_dev}p2" 2>/dev/null || true
    mkfs.ext4 -L ROOTFS "${loop_dev}p3" 2>/dev/null || true

    local efi_mnt=$(mktemp -d)
    local boot_mnt=$(mktemp -d)

    mount "${loop_dev}p1" "$efi_mnt"
    mount "${loop_dev}p2" "$boot_mnt"
    mount "${loop_dev}p3" "$rootfs_mnt"

    if [ -n "$abl_path" ] && [ -f "$abl_path" ]; then
        mkdir -p "$efi_mnt/EFI/BOOT"
        cp "$abl_path" "$efi_mnt/EFI/BOOT/"
        echo "ABL 已安装到 EFI 分区"
    fi

    if [ -f "$rootfs_img" ]; then
        mount -o loop,ro "$rootfs_img" "$tmp_mnt" 2>/dev/null || true
        if [ -d "$tmp_mnt/boot" ]; then
            cp -r "$tmp_mnt/boot"/* "$boot_mnt/" 2>/dev/null || true
        fi
        if [ -d "$tmp_mnt/lib" ]; then
            cp -a "$tmp_mnt"/* "$rootfs_mnt/" 2>/dev/null || true
        fi
        umount "$tmp_mnt" 2>/dev/null || true
    fi

    umount "$efi_mnt" "$boot_mnt" "$rootfs_mnt" 2>/dev/null || true
    losetup -d "$loop_dev" 2>/dev/null || true
    rm -rf "$efi_mnt" "$boot_mnt" "$tmp_mnt" "$rootfs_mnt"

    cat > "$output_dir/flash_sd.sh" <<'FLEOF'
#!/bin/bash
# 将游戏系统刷写到 SD 卡
set -euo pipefail

if [ "$#" -lt 1 ]; then
    echo "用法: $0 /dev/sdX [image_path]"
    echo ""
    echo "查找可用设备:"
    lsblk -d -o NAME,SIZE,TYPE,MOUNTPOINT | grep disk
    exit 1
fi

DEVICE="$1"
IMAGE="${2:-xiaomi-sheng-gaming-os.img}"

if [ ! -b "$DEVICE" ]; then
    echo "错误: $DEVICE 不是有效的块设备"
    exit 1
fi

echo "警告: 将把 $IMAGE 写入 $DEVICE"
echo "此操作将覆盖 $DEVICE 上的所有数据！"
read -p "确认继续? (输入 YES 确认): " confirm
if [ "$confirm" != "YES" ]; then
    echo "已取消"
    exit 0
fi

echo "正在写入 $IMAGE 到 $DEVICE ..."
dd if="$IMAGE" of="$DEVICE" bs=4M status=progress conv=fsync

echo "同步中..."
sync

echo "完成！已将游戏系统写入 SD 卡"
echo "将 SD 卡插入设备，按住 VOL- 键开机进入 ABL 菜单选择启动"
FLEOF
    chmod +x "$output_dir/flash_sd.sh"

    echo "SD 卡镜像已创建: $sd_img"
    echo "刷写脚本: $output_dir/flash_sd.sh"
}

# ---------------------------------------------------------------------------
# setup_gaming_quirks  — 游戏专用硬件适配
#   参数: <rootdir>
# ---------------------------------------------------------------------------
setup_gaming_quirks() {
    local rootdir="$1"

    mkdir -p "$rootdir/etc/security/limits.d"
    cat > "$rootdir/etc/security/limits.d/99-gaming.conf" <<'GQEOF'
# Gaming realtime priority
@audio   -  rtprio     95
@audio   -  memlock    unlimited
luser    -  nice       -10
luser    -  rtprio     90
GQEOF

    cat > "$rootdir/etc/sysctl.d/99-gaming.conf" <<'GSYEOF'
# Gaming performance tuning
vm.swappiness=10
vm.vfs_cache_pressure=50
kernel.sched_autogroup_enabled=1
kernel.sched_child_runs_first=1
GSYEOF

    echo "游戏硬件适配完成"
}
