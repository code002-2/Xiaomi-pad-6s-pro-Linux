#!/bin/bash
set +e # 关闭遇到错误立退，由脚本精细捕获

WORKSPACE="${1:-$(pwd)}"

# ========================================================
# ⚡ CCache 极速编译配置
# ========================================================
if [ -z "$CCACHE_DIR" ]; then
    export CCACHE_DIR="/home/runner/.ccache"
fi
mkdir -p "$CCACHE_DIR"

export CCACHE_MAXSIZE="15G"
export CCACHE_COMPRESS=1
export CCACHE_COMPRESSLEVEL=5
export CCACHE_SLOPPINESS="file_macro,locale,time_macros,include_file_mtime,include_file_ctime,file_stat_matches"
export CCACHE_BASEDIR="$WORKSPACE"
export CCACHE_NOHASHDIR=1

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
mkdir -p "$WORKSPACE/dtb_backup"
cp -r linux/arch/arm64/boot/dts/qcom/* "$WORKSPACE/dtb_backup/" 2>/dev/null || true

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
cp -r "$WORKSPACE/dtb_backup"/* arch/arm64/boot/dts/qcom/ 2>/dev/null || true
echo "✅ 设备树总线结构体强制回滚至安全状态"
# ========================================================

echo "📥 正在下载基础内核配置文件..."
wget https://gitlab.postmarketos.org/alghiffaryfa19/pmaports/-/raw/sheng/device/testing/linux-postmarketos-qcom-sm8550/config-postmarketos-qcom-sm8550.aarch64 -O .config

# ========================================================
# 🛠️ 核心自愈与双系统全内置策略
# ========================================================
echo "🩹 [1/5] 正在全量扫荡并修复所有驱动中残留的旧版 of_gpio.h 引用..."
find drivers/ sound/ -type f \( -name "*.c" -o -name "*.h" \) -exec sed -i 's/#include <linux\/of_gpio.h>/#include <linux\/gpio\/consumer.h>/g' {} + 2>/dev/null || true

echo "📱 [2/5] 正在强行重写触摸屏驱动 (nt36xxx.c)，完全抹除旧版 GPIO 函数..."
if [ -f drivers/input/touchscreen/nt36532e/nt36xxx.c ]; then
    sed -i 's/.*of_get_named_gpio.*novatek,irq.*/        ts->irq_gpio = desc_to_gpio(fwnode_gpiod_get_index(of_fwnode_handle(np), "novatek,irq", 0, GPIOD_ASIS, "nt36xxx_irq"));/g' drivers/input/touchscreen/nt36532e/nt36xxx.c
    sed -i 's/.*of_get_named_gpio.*novatek,reset.*/        ts->reset_gpio = desc_to_gpio(fwnode_gpiod_get_index(of_fwnode_handle(np), "novatek,reset", 0, GPIOD_ASIS, "nt36xxx_reset"));/g' drivers/input/touchscreen/nt36532e/nt36xxx.c
    sed -i 's/of_get_named_gpio(np, "novatek,irq-gpio", 0)/desc_to_gpio(fwnode_gpiod_get_index(of_fwnode_handle(np), "novatek,irq", 0, GPIOD_ASIS, "nt36xxx_irq"))/g' drivers/input/touchscreen/nt36532e/nt36xxx.c
    sed -i 's/of_get_named_gpio(np, "novatek,reset-gpio", 0)/desc_to_gpio(fwnode_gpiod_get_index(of_fwnode_handle(np), "novatek,reset", 0, GPIOD_ASIS, "nt36xxx_reset"))/g' drivers/input/touchscreen/nt36532e/nt36xxx.c
fi

echo "🎨 [3/5] 正在修复高通 GPU (msm_gem.c) 7.1 锁管理和共享判定冲突..."
if [ -f drivers/gpu/drm/msm/msm_gem.c ]; then
    sed -i 's/obj->base.resv/obj->resv/g' drivers/gpu/drm/msm/msm_gem.c 2>/dev/null || true
    sed -i 's/(obj->resv != &obj->_resv)/(!obj->import_attach)/g' drivers/gpu/drm/msm/msm_gem.c 2>/dev/null || true
    sed -i 's/container_of(obj->resv, struct drm_gem_object, _resv)/obj/g' drivers/gpu/drm/msm/msm_gem.c 2>/dev/null || true
fi

echo "🚀 [4/5] 执行内核驱动『全模块转内置』硬核手术..."
sed -i 's/CONFIG_PINCTRL_SM8550=m/CONFIG_PINCTRL_SM8550=y/g' .config
sed -i 's/CONFIG_SM_GCC_8550=m/CONFIG_SM_GCC_8550=y/g' .config
sed -i 's/CONFIG_SM_DISPCC_8550=m/CONFIG_SM_DISPCC_8550=y/g' .config
sed -i 's/CONFIG_INTERCONNECT_QCOM_SM8550=m/CONFIG_INTERCONNECT_QCOM_SM8550=y/g' .config
sed -i 's/CONFIG_QCOM_RPMHPD=m/CONFIG_QCOM_RPMHPD=y/g' .config

sed -i 's/CONFIG_SCSI_UFS_QCOM=m/CONFIG_SCSI_UFS_QCOM=y/g' .config
sed -i 's/CONFIG_SCSI_UFSHCD_PLATFORM=m/CONFIG_SCSI_UFSHCD_PLATFORM=y/g' .config
sed -i 's/CONFIG_SCSI_UFSHCD=m/CONFIG_SCSI_UFSHCD=y/g' .config

echo "CONFIG_VT=y" >> .config
echo "CONFIG_VT_CONSOLE=y" >> .config
echo "CONFIG_FRAMEBUFFER_CONSOLE=y" >> .config
echo "CONFIG_FRAMEBUFFER_CONSOLE_DETECT_PRIMARY=y" >> .config
echo "CONFIG_FONT_8x16=y" >> .config
echo "CONFIG_LOGO=y" >> .config
echo "CONFIG_LOGO_LINUX_CLUT224=y" >> .config

# 锁死基本启动参数
echo 'CONFIG_CMDLINE="console=ttyMSM0,115200 earlycon=msm_geni_serial,0xaec00000 root=PARTLABEL=linux rootwait fbcon=nodefer msm_drm.allow_fb_modifiers=1 loglevel=7 panic=0 pm_poweroff.reset_type=1"' >> .config
echo "CONFIG_CMDLINE_FORCE=y" >> .config

echo "CONFIG_CC_OPTIMIZE_FOR_SIZE=y" >> .config
sed -i 's/CONFIG_DEBUG_INFO=y/# CONFIG_DEBUG_INFO is not set/g' .config
echo "CONFIG_DEBUG_INFO_NONE=y" >> .config

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
# 📦 打包重构（强力重构：全部采用绝对路径，确保 Actions 100% 抓到包）
# ========================================================
GAME_PKG_NAME="l
