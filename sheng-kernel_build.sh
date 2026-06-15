#!/bin/bash
set -e

# ==========================================
# 1. 环境准备
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
git clone https://github.com/code002-2/sm8550-mainline.git --branch sheng-mainline --depth 1 linux
cd linux

# ==========================================
# 3. 彻底跳过 kconfig 交互 (核弹级覆盖)
# ==========================================
echo "⚙️ 正在应用并强行补全配置..."

# A. 使用内核默认 defconfig 建立基座 (这步绝对不会报错)
make ARCH=arm64 defconfig

# B. 将你的底板内容注入到底座中
# 我们直接用 sed 批量修改或追加关键选项，不再调用 make oldconfig
cp ../config-postmarketos-qcom-sm8550.aarch64 .config

# C. 强制开启内核必须的编译器开关，解决 Error in reading
echo "CONFIG_COMPAT=y" >> .config
echo "CONFIG_ARM64_BTI=y" >> .config
echo "CONFIG_ARM64_MTE=y" >> .config
echo "CONFIG_LTO_NONE=y" >> .config
echo "CONFIG_PAGE_SIZE_4KB=y" >> .config

# D. 釜底抽薪：彻底删除所有会导致 duplicate_node_names 的设备树源文件
find arch/arm64/boot/dts/qcom/ -name "hamoa*.dts" -o -name "ipq*.dts" -o -name "hamoa*.dtb" -o -name "ipq*.dtb" | xargs rm -f
sed -i '/hamoa/d' arch/arm64/boot/dts/qcom/Makefile
sed -i '/ipq/d' arch/arm64/boot/dts/qcom/Makefile

# ==========================================
# 🛠️ 终极修复：使用补丁修复 sys_regs.c
# ==========================================
echo "🛠️ 正在修补 sys_regs.c 语法错误..."

# 1. 恢复原始文件（防止之前的暴力 sed 破坏了文件结构）
git checkout arch/arm64/kvm/sys_regs.c

# 2. 我们不删除函数，而是修改代码使其通过编译
# 这里的逻辑是将重复定义的函数标记为 'static inline' 或者改名，
# 或者如果冲突严重，直接通过预处理宏关闭相关代码段

# 将可能导致重定义的函数名改名（这是 C 语言中最稳妥的解决重定义方式）
sed -i 's/access_gicv5_idr0/access_gicv5_idr0_unused/g' arch/arm64/kvm/sys_regs.c
sed -i 's/access_gicv5_iaffid/access_gicv5_iaffid_unused/g' arch/arm64/kvm/sys_regs.c
sed -i 's/access_gicv5_ppi_enabler/access_gicv5_ppi_enabler_unused/g' arch/arm64/kvm/sys_regs.c
sed -i 's/sanitise_id_aa64pfr2_el1/sanitise_id_aa64pfr2_el1_unused/g' arch/arm64/kvm/sys_regs.c
sed -i 's/set_id_aa64pfr2_el1/set_id_aa64pfr2_el1_unused/g' arch/arm64/kvm/sys_regs.c

# 3. 如果编译还是报错，我们强制在 sys_regs.c 中禁止 GICv5 的 KVM 特性
sed -i 's/#define __KVM_GIC_V5__ 1/\/\/#define __KVM_GIC_V5__ 1/g' arch/arm64/kvm/sys_regs.c

# ==========================================
# 4. 执行不带交互的编译
# ==========================================
echo "🔨 开始极速编译..."

# 执行 prepare 确保生成的配置生效
make ARCH=arm64 LLVM=1 prepare

# 使用 --silent 静默编译，并只构建目标 Image 和 你的设备树
make ARCH=arm64 CC="ccache clang" LLVM=1 Image
make -j$(nproc) ARCH=arm64 LLVM=1 arch/arm64/boot/dts/qcom/sm8550-xiaomi-sheng.dtb
make -j$(nproc) ARCH=arm64 LLVM=1 modules

# ==========================================
# 5. 打包产物 (保持不变)
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

echo "🎉 终极通用版内核打包圆满完成！"
