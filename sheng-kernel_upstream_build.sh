#!/bin/bash
set +e # 关闭遇到错误立退，由脚本精细捕获

WORKSPACE="${1:-$(pwd)}"

if [ -z "$CCACHE_DIR" ]; then
    export CCACHE_DIR="/home/runner/.ccache"
    export CCACHE_MAXSIZE="10G"
    export CCACHE_SLOPPINESS="file_macro,locale,time_macros"
fi

mkdir -p "$CCACHE_DIR"

export CC="ccache clang"
export CXX="ccache clang++"
export AR="llvm-ar"
export NM="llvm-nm"
export OBJCOPY="llvm-objcopy"
export OBJDUMP="llvm-objdump"
export READELF="llvm-readelf"
export STRIP="llvm-strip"

echo "🌐 正在克隆你的自定义 sm8550-mainline 仓库..."
if git clone https://github.com/code002-2/sm8550-mainline.git --branch "sheng-7.0" --depth 150 linux; then
    echo "✅ 成功克隆基础 sheng-7.0 分支"
else
    echo "⚠️ 未找到 sheng-7.0 分支，尝试克隆默认主分支..."
    git clone https://github.com/code002-2/sm8550-mainline.git --depth 150 linux
fi

echo "🛡️ 正在物理隔离并备份本地验证通过的设备树文件..."
mkdir -p dtb_backup
cp -r linux/arch/arm64/boot/dts/qcom/* dtb_backup/ 2>/dev/null || true

cd linux

# ========================================================
# 🔄 步骤：精准拉取 Linus Mainline 官方主线最新 7.1 开发树
# ========================================================
echo "📡 正在连接 Linus Mainline 官方主线内核仓库..."
git remote add upstream-mainline https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git

echo "📥 拒绝 Tags 干扰，仅精准拉取上游 master 分支最新提交..."
git fetch upstream-mainline master --depth 50 --no-tags

UPSTREAM_TARGET="upstream-mainline/master"
echo "🎯 成功锁定 Linux 7.1 开发主线上游目标: $UPSTREAM_TARGET"

echo "🔀 正在将最新 7.1 补丁自动无损合并到你的代码中..."
git config user.name "github-actions[bot]"
git config user.email "github-actions[bot]@users.noreply.github.com"

if git merge "$UPSTREAM_TARGET" --no-edit; then
    echo "✅ 完美！上游 7.1 主线最新补丁已无缝合并。"
else
    echo "❌ 警告：自动合并冲突，启动防御机制..."
    git merge --abort
    git merge "$UPSTREAM_TARGET" --no-edit -X ours
    echo "⚠️ 已通过 Ours 策略强制完成 7.1 补丁合并。"
fi

echo "♻️ 正在强行还原稳定的高通小米设备树，覆盖 7.1 错乱节点..."
cp -r ../dtb_backup/* arch/arm64/boot/dts/qcom/ 2>/dev/null || true
echo "✅ 设备树总线结构体强制回滚至安全状态"
# ========================================================

echo "📥 正在下载基础内核配置文件..."
wget https://gitlab.postmarketos.org/alghiffaryfa19/pmaports/-/raw/sheng/device/testing/linux-postmarketos-qcom-sm8550/config-postmarketos-qcom-sm8550.aarch64 -O .config

# ========================================================
# 🛠️ 核心自愈与极致瘦身：解决内存越界硬卡死
# ========================================================
echo "🩹 [1/5] 正在全量扫荡并修复所有驱动中残留的旧版 of_gpio.h 引用..."
find drivers/ sound/ -type f \( -name "*.c" -o -name "*.h" \) -exec sed -i 's/#include <linux\/of_gpio.h>/#include <linux\/gpio\/consumer.h>/g' {} + 2>/dev/null || true

echo "📱 [2/5] 正在使用 7.1 正统 fwnode 架构重写触摸屏驱动 (nt36xxx.c)..."
if [ -f drivers/input/touchscreen/nt36532e/nt36xxx.c ]; then
    sed -i 's/ts->irq_gpio = .*/ts->irq_gpio = desc_to_gpio(fwnode_gpiod_get_index(of_fwnode_handle(np), "novatek,irq", 0, GPIOD_ASIS, "nt36xxx_irq"));/g' drivers/input/touchscreen/nt36532e/nt36xxx.c
    sed -i 's/.*reset-gpio.*/ts->reset_gpio = desc_to_gpio(fwnode_gpiod_get_index(of_fwnode_handle(np), "novatek,reset", 0, GPIOD_ASIS, "nt36xxx_reset"));/g' drivers/input/touchscreen/nt36532e/nt36xxx.c
fi

echo "🎨 [3/5] 正在修复高通 GPU (msm_gem.c) 7.1 锁管理和共享判定冲突..."
if [ -f drivers/gpu/drm/msm/msm_gem.c ]; then
    sed -i 's/obj->base.resv/obj->resv/g' drivers/gpu/drm/msm/msm_gem.c 2>/dev/null || true
    sed -i 's/(obj->resv != &obj->_resv)/(!obj->import_attach)/g' drivers/gpu/drm/msm/msm_gem.c 2>/dev/null || true
    sed -i 's/container_of(obj->resv, struct drm_gem_object, _resv)/obj/g' drivers/gpu/drm/msm/msm_gem.c 2>/dev/null || true
fi

echo "🚀 [4/5] 正在注入高通主线显示核心与底座 Regulator 电源保活指令..."
echo "CONFIG_DRM_MSM=y" >> .config

# 强行锁死高通电源总线控制器，防止 7.1 自动剔除导致断电黑屏
echo "CONFIG_REGULATOR=y" >> .config
echo "CONFIG_REGULATOR_QCOM=y" >> .config
echo "CONFIG_REGULATOR_QCOM_RPMH=y" >> .config
echo "CONFIG_REGULATOR_QCOM_SMD=y" >> .config

# 基础显示面板与背光保活
echo "CONFIG_DRM_PANEL=y" >> .config
echo "CONFIG_DRM_PANEL_SIMPLE=y" >> .config
echo "CONFIG_BACKLIGHT_CLASS_DEVICE=y" >> .config
echo "CONFIG_BACKLIGHT_GPIO=y" >> .config

# 保持极致瘦身，确保内核体积不复胖
echo "CONFIG_CC_OPTIMIZE_FOR_SIZE=y" >> .config
sed -i 's/CONFIG_DEBUG_INFO=y/# CONFIG_DEBUG_INFO is not set/g' .config
echo "CONFIG_DEBUG_INFO_NONE=y" >> .config

# ntsync 作为实验特性，目前保持屏蔽状态（对照组排查法）
# echo "CONFIG_NTSYNC=y" >> .config
# echo "CONFIG_ANON_INODES=y" >> .config

# ========================================================
# 🏷️ [5/5] 核心改名
# ========================================================
echo "🏷️ 正在向内核配置系统注入自定义版本后缀: -xiaomi-pad-6s-pro-game"
sed -i '/CONFIG_LOCALVERSION/d' .config
echo 'CONFIG_LOCALVERSION="-xiaomi-pad-6s-pro-game"' >> .config

echo "🔄 正在针对新合并的 7.1 内核自动刷新 Kconfig 选项..."
make ARCH=arm64 LLVM=1 olddefconfig

# ========================================================
# 🔨 精准编译
# ========================================================
echo "🔨 开始编译内核 Image, Image.gz, 内核模块和设备树..."
make -j$(nproc) ARCH=arm64 CC="ccache clang" LLVM=1 Image Image.gz modules dtbs 2> build_error.log
MAKE_EXIT_CODE=$?

if [ $MAKE_EXIT_CODE -ne 0 ]; then
    echo ""
    echo "❌❌❌ 编译不幸中断！以下是脚本为你捕获的 Clang 核心报错日志 ❌❌❌"
    echo "========================================================================="
    grep -B 3 -A 5 -i "error:" build_error.log || tail -n 80 build_error.log
    echo "========================================================================="
    exit $MAKE_EXIT_CODE
fi

set -e 

_kernel_version="$(make kernelrelease -s)"
echo "📦 最终构建出的内核定制版本号为: ${_kernel_version}"

# ========================================================
# 📦 打包重构：使用安全大内存布局 + 亮屏调试 CMDLINE
# ========================================================
GAME_PKG_NAME="linux-xiaomi-pad-6s-pro-game"
PKGDIR="../${GAME_PKG_NAME}"

if [ -d "../linux-xiaomi-sheng/DEBIAN" ]; then
    mkdir -p "$PKGDIR"
    cp -r ../linux-xiaomi-sheng/DEBIAN "$PKGDIR/"
    sed -i "s/Package:.*/Package: ${GAME_PKG_NAME}/" "${PKGDIR}/DEBIAN/control"
    sed -i "s/Version:.*/Version: ${_kernel_version}/" "${PKGDIR}/DEBIAN/control"
else
    mkdir -p "${GRID}/DEBIAN"
    echo "Package: ${GAME_PKG_NAME}" > "${PKGDIR}/DEBIAN/control"
    echo "Version: ${_kernel_version}" >> "${PKGDIR}/DEBIAN/control"
    echo "Architecture: arm64" >> "${PKGDIR}/DEBIAN/control"
    echo "Maintainer: github-actions" >> "${PKGDIR}/DEBIAN/control"
    echo "Description: Upstream 7.1 Linux kernel with power-keepalive for Xiaomi Pad 6S Pro Game" >> "${PKGDIR}/DEBIAN/control"
fi

ARCH=arm64
mkdir -p $PKGDIR/boot

if [ -f arch/$ARCH/boot/Image.gz ]; then
    install -Dm644 arch/$ARCH/boot/Image.gz $PKGDIR/boot/Image.gz
else
    gzip -c arch/$ARCH/boot/Image > arch/$ARCH/boot/Image.gz
    install -Dm644 arch/$ARCH/boot/Image.gz $PKGDIR/boot/Image.gz
fi

install -Dm644 arch/$ARCH/boot/dts/qcom/sm8550-xiaomi-sheng.dtb $PKGDIR/boot/sm8550-xiaomi-sheng.dtb
install -Dm644 .config $PKGDIR/boot/config-${_kernel_version}
install -Dm644 System.map $PKGDIR/boot/System.map-${_kernel_version}
    
chmod +x ../mkbootimg
cat arch/arm64/boot/Image.gz arch/arm64/boot/dts/qcom/sm8550-xiaomi-sheng.dtb > Image.gz-dtb_game
install -Dm644 Image.gz-dtb_game $PKGDIR/boot/Image.gz-dtb_game
mv Image.gz-dtb_game zImage_game

# 🚨 终极亮屏调试 CMDLINE 策略：
# 强制开启控制台打印、提高日志等级到 7、禁止 Panic 自动重置，以此来逼迫黑屏阶段留出调试窗口。
NEW_CMDLINE="console=ttyMSM0,115200 earlycon=msm_geni_serial,0xaec00000 root=PARTLABEL=linux loglevel=7 panic=0 pm_poweroff.reset_type=1"

echo "📱 正在组装 Android [亮屏调试防黑防PanicReset] 刷机镜像 boot.img..."
../mkbootimg --kernel zImage_game --cmdline "${NEW_CMDLINE}" --base 0x00000000 --kernel_offset 0x00080000 --ramdisk_offset 0x01000000 --tags_offset 0x00000100 --dtb_offset 0x01f00000 --pagesize 4096 --id -o ../boot_pad6spro_game_dualboot.img
../mkbootimg --kernel zImage_game --cmdline "${NEW_CMDLINE}" --base 0x00000000 --kernel_offset 0x00080000 --ramdisk_offset 0x01000000 --tags_offset 0x00000100 --dtb_offset 0x01f00000 --pagesize 4096 --id -o ../boot_pad6spro_game_singleboot.img

echo "🧱 安装内核模块..."
make -j$(nproc) ARCH=arm64 CC="ccache clang" LLVM=1 INSTALL_MOD_PATH=$PKGDIR modules_install
rm -rf $PKGDIR/lib/modules/**/build
cd ..

echo "🧬 拉取固件与外设配置..."
git clone https://github.com/map220v/sheng-firmware --depth 1
mkdir -p firmware-xiaomi-sheng/usr/lib/firmware
cp -r sheng-firmware/* firmware-xiaomi-sheng/usr/lib/firmware/
rm -rf sheng-firmware

git clone https://github.com/alghiffaryfa19/alsa-sheng --depth 1
cp -r alsa-sheng/* alsa-xiaomi-sheng/
rm -rf alsa-sheng

mkdir -p "${GAME_PKG_NAME}/DEBIAN" firmware-xiaomi-sheng/DEBIAN alsa-xiaomi-sheng/DEBIAN sheng-devauth/DEBIAN

echo "📦 正在执行打包..."
dpkg-deb --build --root-owner-group "$GAME_PKG_NAME"
dpkg-deb --build --root-owner-group firmware-xiaomi-sheng
dpkg-deb --build --root-owner-group alsa-xiaomi-sheng

if [ -d "sheng-devauth" ]; then
    dpkg-deb --build --root-owner-group sheng-devauth
fi

echo "🎉 全套亮屏调试安全版内核构建任务圆满结束！"
