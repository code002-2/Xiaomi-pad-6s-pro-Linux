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
echo "📥 正在拉取内核源码..."
git clone https://github.com/code002-2/sm8550-mainline.git --branch sheng-mainline --depth 1 linux
cd linux

# ==========================================
# 3. 智能配置注入 (底座 + 高通专有补丁合并)
# ==========================================
echo "⚙️ 正在应用自动生成的底座配置..."

# 1. 复制干净底座
cp ../sm8550.config .config

# 2. 精准提取高通、小米等专属驱动
echo "🔍 正在从 postmarketos 提取专有配置..."
grep -E '^CONFIG_.*(QCOM|MSM|SM8550|XIAOMI|ADRENO)=' ../config-postmarketos-qcom-sm8550.aarch64 > qcom_extras.config || true

# 3. 强制内置核心驱动
sed -i 's/=m/=y/g' qcom_extras.config

# 4. 合并补丁
cat qcom_extras.config >> .config

# 5. 硬编码保底驱动与冲突屏蔽
{
    echo "# ---- 核心亮机保底驱动 (防止跨版本丢失) ----"
    echo "CONFIG_SCSI_UFS_QCOM=y"
    echo "CONFIG_PHY_QCOM_QMP_UFS=y"
    echo "CONFIG_DRM_MSM=y"
    echo "CONFIG_DRM_MSM_DPU=y"
    echo "CONFIG_DRM_PANEL_XIAOMI_SHENG=y"
    echo "CONFIG_QCOM_SPMI_PMIC=y"
    echo "CONFIG_USB_DWC3_QCOM=y"
    
    echo "# ---- 屏蔽冲突项 (KVM 与 第三方网卡) ----"
    echo "# CONFIG_KVM is not set"
    echo "# CONFIG_KVM_ARM_VGIC_V3 is not set"
    echo "# CONFIG_KVM_ARM_VGIC_V2 is not set"
    echo "# CONFIG_ARM64_VIRT is not set"
    echo "# CONFIG_WLAN_VENDOR_INTEL is not set"
    echo "# CONFIG_IWLWIFI is not set"
    echo "# CONFIG_WLAN_VENDOR_REALTEK is not set"
    echo "# CONFIG_WLAN_VENDOR_MEDIATEK is not set"
    echo "# CONFIG_WLAN_VENDOR_BROADCOM is not set"
} >> .config

# 6. 安全融合并补全依赖
echo "🔄 正在自动融合配置..."
make ARCH=arm64 olddefconfig

# ==========================================
# 4. 彻底清空 KVM 冲突源
# ==========================================
echo "🧹 正在清理 KVM 冲突文件..."
find arch/arm64/kvm/ -name "*.c" -type f -delete
find arch/arm64/kvm/ -name "*.h" -type f -delete
echo "obj- := empty.o" > arch/arm64/kvm/Makefile

# ==========================================
# 5. 执行强制编译
# ==========================================
echo "🔨 开始极速编译..."

# 编译核心 Image
make -j$(nproc) ARCH=arm64 LLVM=1 Image

# 压缩内核镜像
echo "🗜️ 正在压缩内核镜像..."
gzip -c arch/arm64/boot/Image > arch/arm64/boot/Image.gz

# 强制编译设备树 (使用 -f 忽略重复节点错误)
make -j$(nproc) ARCH=arm64 LLVM=1 DTC_FLAGS="-f" qcom/sm8550-xiaomi-sheng.dtb

# 编译所有必须的动态模块
make -j$(nproc) ARCH=arm64 LLVM=1 modules

# ==========================================
# 6. 产物体检
# ==========================================
echo "📊 核心产物大小检查："
ls -lh arch/arm64/boot/Image arch/arm64/boot/Image.gz arch/arm64/boot/dts/qcom/sm8550-xiaomi-sheng.dtb

if [ ! -f "arch/arm64/boot/Image.gz" ]; then
    echo "❌ 严重错误：Image.gz 依然不存在！"
    exit 1
fi

# ==========================================
# 7. 打包内核镜像 与 导出内核模块
# ==========================================
echo "📦 正在导出内核模块并生成 boot.img..."
_kernel_version="$(make kernelrelease -s)"
PKGDIR=../linux-xiaomi-sheng

mkdir -p $PKGDIR/boot

# 1. 【核心修复】将内核模块导出到目标包目录中
make ARCH=arm64 INSTALL_MOD_PATH=$PKGDIR modules_install

# 2. 拷贝内核核心文件
install -Dm644 arch/arm64/boot/Image.gz $PKGDIR/boot/Image.gz
install -Dm644 arch/arm64/boot/dts/qcom/sm8550-xiaomi-sheng.dtb $PKGDIR/boot/sm8550-xiaomi-sheng.dtb
install -Dm644 .config $PKGDIR/boot/config-${_kernel_version}

# 3. 打包 mkbootimg (单双系统适配)
chmod +x ../mkbootimg
cat arch/arm64/boot/Image.gz arch/arm64/boot/dts/qcom/sm8550-xiaomi-sheng.dtb > Image.gz-dtb_sheng
mv Image.gz-dtb_sheng zImage_sheng

../mkbootimg --kernel zImage_sheng --cmdline "root=PARTLABEL=linux rootwait rw" --base 0x00000000 --kernel_offset 0x00008000 --tags_offset 0x01e00000 --pagesize 4096 --id -o ../boot_sheng_dualboot.img
../mkbootimg --kernel zImage_sheng --cmdline "root=PARTLABEL=userdata rootwait rw" --base 0x00000000 --kernel_offset 0x00008000 --tags_offset 0x01e00000 --pagesize 4096 --id -o ../boot_sheng_singleboot.img

# ==========================================
# 8. 组装与构建 DEB 包 (固件拉取 + UsrMerge)
# ==========================================
cd ..

echo "📥 正在从上游拉取最新的固件文件..."
# 克隆外部固件库 (加深 depth 提高速度)
git clone --depth 1 https://github.com/lzxcr/linux-firmware-sheng.git /tmp/temp_fw

echo "🔧 正在将固件注入打包目录，并强制转入 /usr/lib..."
mkdir -p firmware-xiaomi-sheng/usr/lib

# 智能识别上游结构并拷贝
if [ -d "/tmp/temp_fw/lib" ]; then
    cp -r /tmp/temp_fw/lib/* firmware-xiaomi-sheng/usr/lib/
else
    cp -r /tmp/temp_fw/* firmware-xiaomi-sheng/usr/lib/ 2>/dev/null || true
fi
rm -rf /tmp/temp_fw

echo "🔧 正在对内核及其他模块进行 UsrMerge (解决 Arch Linux 安装报错)..."
# 【核心修复】不仅改造音频，还将生成的内核模块包也做 UsrMerge
for pkg in linux-xiaomi-sheng alsa-xiaomi-sheng; do
    if [ -d "$pkg/lib" ]; then
        echo "✅ 正在将 $pkg 中的 /lib 迁移至 /usr/lib"
        mkdir -p "$pkg/usr"
        mv "$pkg/lib" "$pkg/usr/"
    fi
done

echo "📦 开始构建符合全平台规范的 .deb 文件..."
# 按照正确的清单打包 (已剔除不支持的 sensor)
dpkg-deb --build --root-owner-group linux-xiaomi-sheng
dpkg-deb --build --root-owner-group firmware-xiaomi-sheng
dpkg-deb --build --root-owner-group alsa-xiaomi-sheng
dpkg-deb --build --root-owner-group sheng-devauth

echo "🎉 核心编译及重组打包全线通关！"
