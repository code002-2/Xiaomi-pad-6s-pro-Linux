#!/bin/bash
set -euo pipefail

# =============================================================================
# sheng-kernel_build.sh — Unified kernel build script for Xiaomi Pad 6S Pro
# =============================================================================
source "$(dirname "$0")/lib/rootfs-common.sh"
# Controls which kernel branch to build via environment variables:
#   KERNEL_REPO  — GitHub repo (default: code002-2/sm8550-mainline)
#   KERNEL_BRANCH — Git branch (default: sheng-mainline)
#
# Usage:
#   bash sheng-kernel_build.sh                    # mainline (default)
#   KERNEL_REPO=ianchb/sm8550-mainline KERNEL_BRANCH=sheng-7.0.12 bash sheng-kernel_build.sh  # stable
# =============================================================================

# --- ccache configuration ---
if [ -z "${CCACHE_DIR:-}" ]; then
    export CCACHE_DIR="/home/runner/.ccache"
    export CCACHE_MAXSIZE="10G"
    export CCACHE_SLOPPINESS="file_macro,locale,time_macros"
fi
mkdir -p "$CCACHE_DIR"

# --- Compiler toolchain ---
export CC="ccache clang"
export CXX="ccache clang++"
export AR="llvm-ar"
export NM="llvm-nm"
export OBJCOPY="llvm-objcopy"
export OBJDUMP="llvm-objdump"
export READELF="llvm-readelf"
export STRIP="llvm-strip"

# --- Kernel repo and branch ---
# Channel controls which kernel source to use (mainline or stable).
# These can be overridden via KERNEL_REPO / KERNEL_BRANCH env vars.
CHANNEL="${KERNEL_CHANNEL:-mainline}"

# Set defaults based on channel, then allow env var override
case "$CHANNEL" in
    stable)
        DEFAULT_REPO="ianchb/sm8550-mainline"
        DEFAULT_BRANCH="sheng-7.1.3"
        ;;
    *)
        DEFAULT_REPO="code002-2/sm8550-mainline"
        DEFAULT_BRANCH="sheng-mainline"
        ;;
esac

KERNEL_REPO="${KERNEL_REPO:-$DEFAULT_REPO}"
KERNEL_BRANCH="${KERNEL_BRANCH:-$DEFAULT_BRANCH}"

echo "Building kernel from https://github.com/${KERNEL_REPO}.git (branch: ${KERNEL_BRANCH})"

# --- Clone kernel source ---
rm -rf linux
git clone "https://github.com/${KERNEL_REPO}.git" --branch "$KERNEL_BRANCH" --depth 1 --single-branch linux
cd linux

# --- Copy kernel config ---
cp ../sm8550.config .config

# --- Compile ---
make -j"$(nproc)" ARCH=arm64 CC="ccache clang" LLVM=1
_kernel_version="$(make -s ARCH=arm64 kernelrelease)"

# --- Update DEBIAN control ---
sed -i "s/Version:.*/Version: ${_kernel_version}/" ../linux-xiaomi-sheng/DEBIAN/control

PKGDIR=../linux-xiaomi-sheng
ARCH=arm64

# --- Install kernel images ---
mkdir -p "$PKGDIR/boot"

install -Dm644 arch/"$ARCH"/boot/Image.gz \
    "$PKGDIR/boot/Image.gz"

install -Dm644 arch/"$ARCH"/boot/dts/qcom/sm8550-xiaomi-sheng.dtb \
    "$PKGDIR/boot/sm8550-xiaomi-sheng.dtb"

install -Dm644 .config \
    "$PKGDIR/boot/config-${_kernel_version}"

install -Dm644 System.map \
    "$PKGDIR/boot/System.map-${_kernel_version}"

# --- Build boot images ---
if [ -f "../mkbootimg" ]; then
    chmod +x ../mkbootimg
else
    echo "警告: mkbootimg 不存在，跳过 boot.img 构建" >&2
fi

if [ ! -f "arch/$ARCH/boot/Image.gz" ]; then
    echo "错误: 未找到 arch/$ARCH/boot/Image.gz" >&2
    exit 1
fi
if [ ! -f "arch/$ARCH/boot/dts/qcom/sm8550-xiaomi-sheng.dtb" ]; then
    echo "错误: 未找到 sm8550-xiaomi-sheng.dtb" >&2
    exit 1
fi

cat arch/arm64/boot/Image.gz arch/arm64/boot/dts/qcom/sm8550-xiaomi-sheng.dtb > Image.gz-dtb_sheng

install -Dm644 Image.gz-dtb_sheng \
    "$PKGDIR/boot/Image.gz-dtb_sheng"

mv Image.gz-dtb_sheng zImage_sheng

if [ -f "../mkbootimg" ]; then
    ../mkbootimg --kernel zImage_sheng --cmdline "root=PARTLABEL=linux" --base 0x00000000 --kernel_offset 0x00008000 --tags_offset 0x01e00000 --pagesize 4096 --id -o ../boot_sheng_dualboot.img
    ../mkbootimg --kernel zImage_sheng --cmdline "root=PARTLABEL=userdata" --base 0x00000000 --kernel_offset 0x00008000 --tags_offset 0x01e00000 --pagesize 4096 --id -o ../boot_sheng_singleboot.img
fi

# --- Install modules ---
make -j"$(nproc)" ARCH=arm64 CC="ccache clang" LLVM=1 INSTALL_MOD_PATH="../linux-xiaomi-sheng" modules_install

# Safely remove build symlinks in module directories
find "../linux-xiaomi-sheng/lib/modules" -type l -name "build" -delete 2>/dev/null || true

# --- Build EFI boot image ---
if command -v ukify &>/dev/null; then
    # Locate or build initramfs
    INITRAMFS=""
    for candidate in "boot/initramfs-linux.img" "boot/initrd.img-${_kernel_version}" "boot/initramfs-${_kernel_version}.img"; do
        if [ -f "$candidate" ]; then
            INITRAMFS="$candidate"
            break
        fi
    done
    if [ -z "$INITRAMFS" ]; then
        echo "警告: 未找到 initramfs，尝试 dracut 生成..." >&2
        if command -v dracut &>/dev/null; then
            dracut --force "boot/initramfs-linux.img" "$_kernel_version" && INITRAMFS="boot/initramfs-linux.img"
        fi
    fi

    if [ -n "$INITRAMFS" ]; then
        echo "正在构建 EFI 引导镜像 (initramfs: $INITRAMFS)..."
        ukify build \
            --linux="arch/$ARCH/boot/Image.gz" \
            --os-type=linux \
            --cmdline="root=PARTLABEL=linux rw rootwait console=tty0" \
            --initrd="$INITRAMFS" \
            --output="bootaa64.efi"
        install -Dm644 bootaa64.efi "$PKGDIR/boot/bootaa64.efi"
        echo "EFI boot image 构建完成: bootaa64.efi"
    else
        echo "警告: 无法生成 initramfs，跳过 EFI 构建" >&2
    fi
else
    echo "警告: ukify 不可用，跳过 EFI 构建" >&2
fi

cd ..

# --- Firmware injection ---
download_firmware

# --- ALSA UCM2 injection ---
download_alsa_ucm

# --- UsrMerge ---
usr_merge linux-xiaomi-sheng alsa-xiaomi-sheng

# --- Build .deb packages ---
echo "开始构建deb..."
dpkg-deb --root-owner-group --build linux-xiaomi-sheng
dpkg-deb --root-owner-group --build firmware-xiaomi-sheng
dpkg-deb --root-owner-group --build alsa-xiaomi-sheng
dpkg-deb --root-owner-group --build sheng-devauth
