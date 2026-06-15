#!/bin/bash
set -e

# ==========================================
# 1. 编译环境与工具链
# ==========================================
export CCACHE_DIR="/home/runner/.ccache"
export CCACHE_MAXSIZE="10G"
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
# 3. 彻底修复配置冲突
# ==========================================
echo "⚙️ 正在应用并修复配置..."
# 直接将你根目录的配置复制过来
cp ../sm8550.config .config

# 强制重置配置以适配 7.1 版本，自动补全缺失项，消除 Error in reading
make ARCH=arm64 olddefconfig

# 物理删除报错的开发板设备树，防止干扰构建 (釜底抽薪)
find arch/arm64/boot/dts/qcom/ -name "hamoa*.dts" -o -name "ipq*.dts" -o -name "hamoa*.dtb" -o -name "ipq*.dtb" | xargs rm -f || true
sed -i '/hamoa/d' arch/arm64/boot/dts/qcom/Makefile || true
sed -i '/ipq/d' arch/arm64/boot/dts/qcom/Makefile || true

# ==========================================
# 4. 核心编译 (关键：若报错，请移除 -j$(nproc) 观察单核错误)
# ==========================================
echo "🔨 开始编译..."
# 我们显式编译 Image 和目标 dtb，不进行 dtbs 全量扫描
make ARCH=arm64 CC="ccache clang" LLVM=1 Image
make ARCH=arm64 CC="ccache clang" LLVM=1 arch/arm64/boot/dts/qcom/sm8550-xiaomi-sheng.dtb
make ARCH=arm64 CC="ccache clang" LLVM=1 modules

# ==========================================
# 5. 打包与产物提取 (保持不变)
# ==========================================
_kernel_version="$(make kernelrelease -s)"
PKGDIR=../linux-xiaomi-sheng
mkdir -p $PKGDIR/boot

install -Dm644 arch/arm64/boot/Image.gz $PKGDIR/boot/Image.gz
install -Dm644 arch/arm64/boot/dts/qcom/sm8550-xiaomi-sheng.dtb $PKGDIR/boot/sm8550-xiaomi-sheng.dtb
install -Dm644 .config $PKGDIR/boot/config-${_kernel_version}

chmod +x ../mkbootimg
cat arch/arm64/boot/Image.gz arch/arm64/boot/dts/qcom/sm8550-xiaomi-sheng.dtb > Image.gz-dtb_sheng
mv Image.gz-dtb_sheng zImage_sheng

../mkbootimg --kernel zImage_sheng --cmdline "root=PARTLABEL=linux rootwait rw" --base 0x00000000 --kernel_offset 0x00008000 --tags_offset 0x01e00000 --pagesize 4096 --id -o ../boot_sheng_dualboot.img
../mkbootimg --kernel zImage_sheng --cmdline "root=PARTLABEL=userdata rootwait rw" --base 0x00000000 --kernel_offset 0x00008000 --tags_offset 0x01e00000 --pagesize 4096 --id -o ../boot_sheng_singleboot.img

echo "🎉 编译完成！"
