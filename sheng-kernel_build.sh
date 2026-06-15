#!/bin/bash
set -e

# ==========================================
# 1. 编译环境与工具链配置
# ==========================================
export CCACHE_DIR="/home/runner/.ccache"
export CCACHE_MAXSIZE="10G"
export CCACHE_SLOPPINESS="file_macro,locale,time_macros"
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
git clone https://github.com/code002-2/sm8550-mainline.git --branch sheng-mainline --depth 1 linux
cd linux

# ==========================================
# 3. 智能定位并应用 sm8550.config
# ==========================================
echo "⚙️ 正在定位并应用配置文件..."

if [ -f "../sm8550.config" ]; then
    echo "✅ 优先检测到根目录配置: ../sm8550.config，正在应用..."
    cp ../sm8550.config .config
elif [ -n "$(find "$GITHUB_WORKSPACE" ../ -maxdepth 2 -name "config*.aarch64*" 2>/dev/null | head -n 1)" ]; then
    CONFIG_PATH=$(find "$GITHUB_WORKSPACE" ../ -maxdepth 2 -name "config*.aarch64*" 2>/dev/null | head -n 1)
    echo "✅ 使用备用配置: $CONFIG_PATH"
    cp "$CONFIG_PATH" .config
else
    echo "❌ 致命错误: 找不到任何配置文件！"
    exit 1
fi

# 核心：自动适配 7.1 版本差异，防止 Error in reading
make ARCH=arm64 olddefconfig

# 剔除导致编译崩溃的无效开发板设备树节点
sed -i '/hamoa-iot-evk.dtb/d' arch/arm64/boot/dts/qcom/Makefile || true

# ==========================================
# 4. 执行多线程编译
# ==========================================
echo "🔨 开始极速编译..."
make -j$(nproc) ARCH=arm64 CC="ccache clang" LLVM=1
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
make -j$(nproc) ARCH=arm64 CC="ccache clang" LLVM=1 INSTALL_MOD_PATH=../linux-xiaomi-sheng modules_install

# 清理冗余链接
rm -rf ../linux-xiaomi-sheng/lib/modules/*/build || true
rm -rf ../linux-xiaomi-sheng/lib/modules/*/source || true

cd ..

# ==========================================
# 6. 打包固件与驱动
# ==========================================
git clone https://github.com/map220v/sheng-firmware
mkdir -p firmware-xiaomi-sheng/usr/lib/firmware
cp -r sheng-firmware/* firmware-xiaomi-sheng/usr/lib/firmware/

git clone https://github.com/alghiffaryfa19/alsa-sheng
cp -r alsa-sheng/* alsa-xiaomi-sheng/

dpkg-deb --build --root-owner-group linux-xiaomi-sheng
dpkg-deb --build --root-owner-group firmware-xiaomi-sheng
dpkg-deb --build --root-owner-group alsa-xiaomi-sheng
dpkg-deb --build --root-owner-group sheng-devauth

echo "🎉 所有任务圆满完成！"
