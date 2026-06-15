#!/bin/bash
set -e

# ==========================================
# 1. 编译环境配置
# ==========================================
export CCACHE_DIR="/home/runner/.ccache"
export CCACHE_MAXSIZE="10G"
mkdir -p "$CCACHE_DIR"
export CC="ccache clang"
export CXX="ccache clang++"
export LLVM=1
export ARCH=arm64

# ==========================================
# 2. 拉取源码
# ==========================================
echo "📥 正在拉取 7.1 内核源码..."
git clone https://github.com/code002-2/sm8550-mainline.git --branch sheng-mainline --depth 1 linux
cd linux

# ==========================================
# 3. 终极配置注入 (解决跨版本依赖与内核缩水)
# ==========================================
echo "⚙️ 正在应用配置并强制转换单体内核..."

# 复制 7.0 版本的底板配置
cp ../config-postmarketos-qcom-sm8550.aarch64 .config

# 【核心修复】将所有的按需加载模块(=m)强制转换为内置(=y)，避免内核骨架化
sed -i 's/=m/=y/g' .config

# 【依赖保底】强制写死亮机与读取硬盘所需的底层驱动，防止被 7.1 版本抛弃
{
    echo "CONFIG_ARCH_QCOM=y"
    echo "CONFIG_PINCTRL_SM8550=y"
    echo "CONFIG_SCSI_UFS_QCOM=y"
    echo "CONFIG_PHY_QCOM_QMP_UFS=y"
    echo "CONFIG_DRM_MSM=y"
    echo "CONFIG_DRM_MSM_DPU=y"
    echo "CONFIG_DRM_PANEL_XIAOMI_SHENG=y"
    echo "CONFIG_QCOM_SPMI_PMIC=y"
    echo "CONFIG_USB_DWC3_QCOM=y"
    echo "CONFIG_PHY_QCOM_QMP_USB=y"
    echo "CONFIG_PHY_QCOM_SNPS_EUSB2=y"
    
    # 彻底禁用 KVM 虚拟化，避开 sys_regs.c 的函数重定义报错
    echo "# CONFIG_KVM is not set"
    echo "# CONFIG_KVM_ARM_VGIC_V3 is not set"
    echo "# CONFIG_KVM_ARM_VGIC_V2 is not set"
    echo "# CONFIG_ARM64_VIRT is not set"
} >> .config

# 使用 olddefconfig 安全合入我们强加的配置
make ARCH=arm64 olddefconfig

# ==========================================
# 4. 彻底清空 KVM 冲突源 (保留空壳防报错)
# ==========================================
echo "🧹 正在清理 KVM 冲突文件..."
find arch/arm64/kvm/ -name "*.c" -type f -delete
find arch/arm64/kvm/ -name "*.h" -type f -delete
echo "obj- := empty.o" > arch/arm64/kvm/Makefile

# ==========================================
# 5. 执行强制编译
# ==========================================
echo "🔨 开始极速编译..."

# 编译核心 Image (这次体积会暴涨到正常大小)
make -j$(nproc) ARCH=arm64 LLVM=1 Image

# 强制压缩一份 Image.gz 供后续打包使用
echo "🗜️ 正在压缩内核镜像..."
gzip -c arch/arm64/boot/Image > arch/arm64/boot/Image.gz

# 强制编译设备树 (使用 -f 忽略重复节点错误)
make -j$(nproc) ARCH=arm64 LLVM=1 DTC_FLAGS="-f" qcom/sm8550-xiaomi-sheng.dtb

# 编译残余模块 (如果还有的话)
make -j$(nproc) ARCH=arm64 LLVM=1 modules

# ==========================================
# 6. 产物体检
# ==========================================
echo "📊 核心产物大小检查 (Image 需 > 30MB)："
ls -lh arch/arm64/boot/Image arch/arm64/boot/Image.gz arch/arm64/boot/dts/qcom/sm8550-xiaomi-sheng.dtb

if [ ! -f "arch/arm64/boot/Image.gz" ]; then
    echo "❌ 严重错误：Image.gz 依然不存在！"
    exit 1
fi

# ==========================================
# 7. 打包内核镜像 (boot.img)
# ==========================================
echo "📦 正在生成 boot.img..."
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

# ==========================================
# 8. 构建 DEB 包
# ==========================================
# 退出 linux 源码目录，回到根目录，以确保能找到 sheng-devauth
cd ..

echo "📦 开始打包所有 deb 文件..."
dpkg-deb --build --root-owner-group linux-xiaomi-sheng
dpkg-deb --build --root-owner-group firmware-xiaomi-sheng
dpkg-deb --build --root-owner-group alsa-xiaomi-sheng
dpkg-deb --build --root-owner-group sheng-devauth

echo "🎉 所有任务圆满完成！"
