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
# ==========================================
# 🛠️ 终极配置修复 (跳过所有交互式菜单)
# ==========================================
echo "⚙️ 正在应用并强行补全配置..."
cp ../sm8550.config .config

# 1. 使用 scripts/kconfig/conf 工具配合 setconfig.sh 自动填充默认值
# 这里的 'silentoldconfig' 或 'olddefconfig' 是关键，它们不会询问
# 但为了彻底解决 choice 菜单问题，我们强制使用 'yes' 并辅以更强的处理
make ARCH=arm64 KCONFIG_ALLCONFIG=.config alldefconfig

# 2. 对缺失项进行最后的“暴力”修复 (确保不会有 NEW 选项卡死)
# 这一步是为了应对那些内核自动生成无法触及的特定硬件开关
echo "CONFIG_DRIVER_DEFERRED_PROBE_TIMEOUT=10" >> .config
echo "# CONFIG_ACPI_APEI_GHES_NVIDIA is not set" >> .config

# ==========================================
# 🛑 终极重置 (在进入 linux 目录并 copy config 后执行)
# ==========================================
cp ../sm8550.config .config

# 强制删除所有可能导致冲突的残留信息
rm -f .config.old
rm -f include/config/auto.conf
rm -f include/config/auto.conf.cmd

# 使用最原始的 make oldconfig，并完全不通过 yes，直接用 echo 喂入一个固定的大量回车
# 这样即便有 choice 菜单，它也会自动选第一项 (通常是默认项)
# 我们生成一个包含 1000 个回车的输入流给它
perl -e 'print "\n" x 1000' | make ARCH=arm64 oldconfig

# ==========================================
# ⚠️ 彻底爆破：物理删除该报错文件，永绝后患
# ==========================================
echo "🛠️ 正在物理移除冲突的设备树文件..."
# 暴力查找并删除，确保它不在编译列表中
rm -f arch/arm64/boot/dts/qcom/hamoa-iot-evk.dts
rm -f arch/arm64/boot/dts/qcom/hamoa-iot-evk.dtb
# 同时确保 Makefile 中没有它的引用
sed -i '/hamoa-iot-evk/d' arch/arm64/boot/dts/qcom/Makefile || true

# 再次运行一次，确保所有依赖更新完全生效
make ARCH=arm64 olddefconfig


# ==========================================
# 4. 极速编译 (精准定位目标)
# ==========================================
echo "🔨 开始极速编译..."

# 1. 先只编译核心内核镜像，不编译全量 dtbs，避开所有无关的设备树报错
make -j$(nproc) ARCH=arm64 CC="ccache clang" LLVM=1 Image

# 2. 精准编译小米平板 6S Pro 的设备树文件
# 这样即便其他开发板有语法错误，也不会影响我们出包
make ARCH=arm64 CC="ccache clang" LLVM=1 dtbs
make ARCH=arm64 CC="ccache clang" LLVM=1 dtbs_install

# 3. 编译内核模块
make -j$(nproc) ARCH=arm64 CC="ccache clang" LLVM=1 modules

# 4. 确认关键产物是否存在
if [ ! -f "arch/arm64/boot/dts/qcom/sm8550-xiaomi-sheng.dtb" ]; then
    echo "❌ 致命错误：小米设备树未找到！"
    exit 1
fi

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
