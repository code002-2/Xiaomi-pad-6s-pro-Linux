#!/bin/bash
set -e

# ==========================================
# 1. 编译环境与工具链配置
# ==========================================
export CCACHE_DIR="$HOME/.ccache"
export CCACHE_MAXSIZE="10G"
export CCACHE_SLOPPINESS="file_macro,locale,time_macros"
export CCACHE_NOHASHDIR="true"
mkdir -p "$CCACHE_DIR"

export CC="ccache clang"
export CXX="ccache clang++"
export AR="llvm-ar"
export NM="llvm-nm"
export OBJCOPY="llvm-objcopy"
export OBJDUMP="llvm-objdump"
export READELF="llvm-readelf"
export STRIP="llvm-strip"

# ==========================================
# 2. 拉取内核源码
# ==========================================
git clone https://github.com/ianchb/sm8550-mainline.git --branch sheng-7.1.0 --depth 1 linux
cd linux

# ==========================================
# 🛠️ 自动配置 (跳过所有交互式菜单)
# ==========================================
echo "⚙️ 正在应用并强行补全配置..."
wget -O .config https://github.com/ianchb/sm8550-mainline/releases/download/7.1.0/sm8550.config
make ARCH=arm64 CC="ccache clang" LLVM=1 olddefconfig
# ==========================================

# ==========================================
# 4. 执行多线程编译
# ==========================================
# 由环境变量 ENABLE_BUILD_LOG 控制是否生成日志文件 (设为 1 或 true 启用)
if [ "${ENABLE_BUILD_LOG:-0}" = "1" ] || [ "${ENABLE_BUILD_LOG:-0}" = "true" ]; then
    LOG_FILE="../build-$(date +%Y%m%d-%H%M%S).log"
    echo "🔨 开始极速编译... (日志: $LOG_FILE)"
    make -j$(nproc) ARCH=arm64 CC="ccache clang" LLVM=1 2>&1 | tee "$LOG_FILE"
    BUILD_EXIT=${PIPESTATUS[0]}
else
    echo "🔨 开始极速编译... (日志已禁用)"
    make -j$(nproc) ARCH=arm64 CC="ccache clang" LLVM=1 2>&1
    BUILD_EXIT=$?
fi
# 检查编译是否成功
if [ $BUILD_EXIT -ne 0 ]; then
    if [ "${ENABLE_BUILD_LOG:-0}" = "1" ] || [ "${ENABLE_BUILD_LOG:-0}" = "true" ]; then
        echo "❌ 编译失败，日志: $LOG_FILE"
    else
        echo "❌ 编译失败"
    fi
    exit 1
fi
_kernel_version="$(make kernelrelease -s)"

# 更新 DEBIAN 版本
sed -i "s/Version:.*/Version: ${_kernel_version}/" ../linux-xiaomi-sheng/DEBIAN/control

# ==========================================
# 5. 提取产物与打包
# ==========================================
PKGDIR=../linux-xiaomi-sheng
mkdir -p $PKGDIR/boot

install -Dm644 arch/arm64/boot/Image.gz $PKGDIR/boot/Image.gz
install -Dm644 arch/arm64/boot/dts/qcom/sm8550-xiaomi-sheng.dtb $PKGDIR/boot/sm8550-xiaomi-sheng.dtb
install -Dm644 .config $PKGDIR/boot/config-${_kernel_version}
install -Dm644 System.map $PKGDIR/boot/System.map-${_kernel_version}

chmod +x ../mkbootimg

# 打包 boot.img
cat arch/arm64/boot/Image.gz arch/arm64/boot/dts/qcom/sm8550-xiaomi-sheng.dtb > Image.gz-dtb_sheng
install -Dm644 Image.gz-dtb_sheng $PKGDIR/boot/Image.gz-dtb_sheng
mv Image.gz-dtb_sheng zImage_sheng

../mkbootimg --kernel zImage_sheng --cmdline "root=PARTLABEL=linux rootwait rw" --base 0x00000000 --kernel_offset 0x00008000 --tags_offset 0x01e00000 --pagesize 4096 --id -o ../boot_sheng_dualboot.img
../mkbootimg --kernel zImage_sheng --cmdline "root=PARTLABEL=userdata rootwait rw" --base 0x00000000 --kernel_offset 0x00008000 --tags_offset 0x01e00000 --pagesize 4096 --id -o ../boot_sheng_singleboot.img

# 编译内核模块
if [ "${ENABLE_BUILD_LOG:-0}" = "1" ] || [ "${ENABLE_BUILD_LOG:-0}" = "true" ]; then
    make -j$(nproc) ARCH=arm64 CC="ccache clang" LLVM=1 INSTALL_MOD_PATH=../linux-xiaomi-sheng modules_install 2>&1 | tee -a "$LOG_FILE"
else
    make -j$(nproc) ARCH=arm64 CC="ccache clang" LLVM=1 INSTALL_MOD_PATH=../linux-xiaomi-sheng modules_install 2>&1
fi

# 清理冗余链接
rm -rf ../linux-xiaomi-sheng/lib/modules/*/build || true
rm -rf ../linux-xiaomi-sheng/lib/modules/*/source || true

cd ..

# ==========================================
# 6. 打包固件与驱动
# ==========================================
# git clone https://github.com/map220v/sheng-firmware
# mkdir -p firmware-xiaomi-sheng/usr/lib/firmware
# cp -r sheng-firmware/* firmware-xiaomi-sheng/usr/lib/firmware/

# git clone https://github.com/alghiffaryfa19/alsa-sheng
# cp -r alsa-sheng/* alsa-xiaomi-sheng/

# ==========================================
# 6.5 构建 fastrpc
# ==========================================
wget -q https://github.com/qualcomm/fastrpc/archive/refs/tags/v1.0.2.zip
unzip -q v1.0.2.zip
cd fastrpc-1.0.2
autoreconf -is
./configure --prefix=/usr --host=aarch64-linux-gnu
make -j$(nproc)
make DESTDIR=$PWD/stage install
cd ..
mkdir -p fastrpc/usr
cp -r fastrpc-1.0.2/stage/usr fastrpc/
find fastrpc/usr/bin -type f -exec chmod +x {} \;
find fastrpc/usr/lib -name "*.so*" -exec chmod +x {} \;

echo "🔧 正在进行 UsrMerge 路径手术 (确保 Arch/Fedora 兼容性)..."

# 对所有可能包含 /lib 目录的包进行自动化修正
for pkg in firmware-xiaomi-sheng alsa-xiaomi-sheng linux-xiaomi-sheng fastrpc; do
    if [ -d "$pkg/lib" ]; then
        echo "✅ 正在将 $pkg 中的 /lib 迁移至 /usr/lib"
        mkdir -p "$pkg/usr"
        mv "$pkg/lib" "$pkg/usr/"
    fi
done


dpkg-deb --build --root-owner-group -Zzstd -z10 linux-xiaomi-sheng
dpkg-deb --build --root-owner-group -Zzstd -z10 firmware-xiaomi-sheng
dpkg-deb --build --root-owner-group -Zzstd -z10 alsa-xiaomi-sheng
dpkg-deb --build --root-owner-group -Zzstd -z10 sheng-devauth
dpkg-deb --build --root-owner-group -Zzstd -z10 fastrpc
dpkg-deb --build --root-owner-group -Zzstd -z10 sheng-sensors

echo "🎉 所有任务圆满完成！"
