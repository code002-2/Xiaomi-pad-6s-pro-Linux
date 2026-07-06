#!/bin/bash
set -euo pipefail

# =============================================================================
# sheng-kernel_build.sh — Unified kernel build script for Xiaomi Pad 6S Pro
# =============================================================================
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
# Channel controls which kernel source to use (mainline or stable)
CHANNEL="${KERNEL_CHANNEL:-mainline}"

case "$CHANNEL" in
    stable)
        KERNEL_REPO="ianchb/sm8550-mainline"
        KERNEL_BRANCH="sheng-7.0.12"
        ;;
    *)
        KERNEL_REPO="code002-2/sm8550-mainline"
        KERNEL_BRANCH="sheng-mainline"
        ;;
esac

# Allow env var override (takes precedence over channel)
KERNEL_REPO="${KERNEL_REPO:-code002-2/sm8550-mainline}"
KERNEL_BRANCH="${KERNEL_BRANCH:-sheng-mainline}"

echo "Building kernel from https://github.com/${KERNEL_REPO}.git (branch: ${KERNEL_BRANCH})"

# --- Clone kernel source ---
git clone "https://github.com/${KERNEL_REPO}.git" --branch "$KERNEL_BRANCH" --depth 1 --single-branch linux
cd linux

# --- Copy kernel config ---
cp ../sm8550.config .config

# --- Compile ---
make -j"$(nproc)" ARCH=arm64 CC="ccache clang" LLVM=1
_kernel_version="$(make kernelrelease -s)"

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
    echo "正在构建 EFI 引导镜像..."
    ukify build \
        --linux="arch/$ARCH/boot/Image.gz" \
        --os-type=linux \
        --cmdline="root=PARTLABEL=linux rw rootwait console=tty0" \
        --initrd="boot/initramfs-linux.img" \
        --output="bootaa64.efi"
    install -Dm644 bootaa64.efi "$PKGDIR/boot/bootaa64.efi"
    echo "EFI boot image 构建完成: bootaa64.efi"
else
    echo "警告: ukify 不可用，跳过 EFI 构建" >&2
fi

cd ..

# --- Firmware injection ---
TMPFW=$(mktemp -d)
git clone --depth 1 --single-branch https://github.com/lzxcr/linux-firmware-sheng.git "$TMPFW/fw"

echo "正在将固件注入打包目录，并强制转入 /usr/lib..."
mkdir -p firmware-xiaomi-sheng/usr/lib
if [ -d "$TMPFW/fw/lib" ]; then
    cp -r "$TMPFW/fw/lib"/* firmware-xiaomi-sheng/usr/lib/
else
    cp -r "$TMPFW/fw"/* firmware-xiaomi-sheng/usr/lib/ 2>/dev/null || true
fi
rm -rf "$TMPFW"

# --- ALSA UCM2 injection ---
mkdir -p alsa-xiaomi-sheng/usr/share/alsa/ucm2
TMPSA=$(mktemp -d)
git clone --depth 1 --single-branch https://github.com/map220v/alsa-ucm-conf.git "$TMPSA/alsa"

if [ -d "$TMPSA/alsa/ucm2" ]; then
    cp -r "$TMPSA/alsa/ucm2"/* alsa-xiaomi-sheng/usr/share/alsa/ucm2/
else
    cp -r "$TMPSA/alsa"/* alsa-xiaomi-sheng/usr/share/alsa/ucm2/ 2>/dev/null || true
fi
rm -rf "$TMPSA"

# --- UsrMerge ---
for pkg in linux-xiaomi-sheng alsa-xiaomi-sheng; do
    if [ -d "$pkg/lib" ]; then
        echo "正在安全融合 $pkg 中的 /lib 至 /usr/lib..."
        mkdir -p "$pkg/usr/lib"
        if ! cp -r "$pkg/lib"/* "$pkg/usr/lib/" 2>/dev/null; then
            echo "错误: 复制 $pkg/lib 失败，中止构建" >&2
            exit 1
        fi
        rm -rf "$pkg/lib"
    fi
done

# --- Build .deb packages ---
echo "开始构建deb..."
dpkg-deb --root-owner-group --build linux-xiaomi-sheng
dpkg-deb --root-owner-group --build firmware-xiaomi-sheng
dpkg-deb --root-owner-group --build alsa-xiaomi-sheng
dpkg-deb --root-owner-group --build sheng-devauth
