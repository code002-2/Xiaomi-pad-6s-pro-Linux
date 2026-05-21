#!/bin/bash
set -e # 遇到任何错误立即停止执行

WORKSPACE="${1:-$(pwd)}"

# 仅在未设置环境变量时配置ccache
if [ -z "$CCACHE_DIR" ]; then
    export CCACHE_DIR="/home/runner/.ccache"
    export CCACHE_MAXSIZE="10G"
    export CCACHE_SLOPPINESS="file_macro,locale,time_macros"
fi

# 确保ccache目录存在
mkdir -p "$CCACHE_DIR"

# 确保ccache优先使用clang
export CC="ccache clang"
export CXX="ccache clang++"
export AR="llvm-ar"
export NM="llvm-nm"
export OBJCOPY="llvm-objcopy"
export OBJDUMP="llvm-objdump"
export READELF="llvm-readelf"
export STRIP="llvm-strip"

echo "🌐 正在克隆你的自定义 sm8550-mainline 仓库..."
# 拉取 150 深度，确保有足够的共同提交历史用于后面的合并
if git clone https://github.com/code002-2/sm8550-mainline.git --branch "sheng-7.0" --depth 150 linux; then
    echo "✅ 成功克隆基础 sheng-7.0 分支"
else
    echo "⚠️ 未找到 sheng-7.0 分支，尝试克隆默认主分支..."
    git clone https://github.com/code002-2/sm8550-mainline.git --depth 150 linux
fi

cd linux

# ========================================================
# 🔄 修正步骤：精准拉取 Linus Mainline 主线最新 7.1 开发树
# ========================================================
echo "📡 正在连接 Linus Mainline 官方主线内核仓库..."
git remote add upstream-mainline https://git.kernel.org/pub/scm/linux/kernel/git/torvalds/linux.git

echo "📥 【核心修复】拒绝 Tags，仅精准拉取上游 master 分支最新提交..."
# 此时上游的 master 分支就是正在推进的 7.1-rcX 核心代码
git fetch upstream-mainline master --depth 50 --no-tags

UPSTREAM_TARGET="upstream-mainline/master"
echo "🎯 成功锁定 Linux 7.1 开发主线上游目标: $UPSTREAM_TARGET"

echo "🔀 正在将最新 7.1 补丁自动无损合并到你的代码中..."
# 配置 Actions 虚拟环境的临时 Git 身份
git config user.name "github-actions[bot]"
git config user.email "github-actions[bot]@users.noreply.github.com"

# 执行合并
if git merge "$UPSTREAM_TARGET" --no-edit; then
    echo "✅ 完美！上游 7.1 主线最新补丁已无缝合并，未发生代码冲突。"
else
    echo "❌ 警告：在上游更新与你的小米平板移植代码合并时发生冲突！"
    echo "📊 冲突文件总览："
    git status --short
    
    echo "🔄 正在启动自动化防御机制：放弃冲突项，强制以你的本地移植代码（Ours）为准..."
    git merge --abort
    # 使用 -X ours 强行推进，确保你为 sheng 写的设备树和关键驱动不被破坏
    git merge "$UPSTREAM_TARGET" --no-edit -X ours
    echo "⚠️ 已通过 Ours 策略强制完成 7.1 补丁合并。"
fi
# ========================================================

echo "📥 正在下载基础内核配置文件..."
wget https://gitlab.postmarketos.org/alghiffaryfa19/pmaports/-/raw/sheng/device/testing/linux-postmarketos-qcom-sm8550/config-postmarketos-qcom-sm8550.aarch64 -O .config

echo "🔄 正在针对新合并的 7.1 内核自动刷新 Kconfig 选项..."
make ARCH=arm64 LLVM=1 olddefconfig

echo "🔨 开始编译内核 Image, Image.gz 和设备树..."
make -j$(nproc) ARCH=arm64 CC="ccache clang" LLVM=1 Image Image.gz dtbs

_kernel_version="$(make kernelrelease -s)"
echo "📦 最终构建出的内核版本号为: ${_kernel_version}"

# 后续的打包与 deb/boot.img 封装逻辑
sed -i "s/Version:.*/Version: ${_kernel_version}/" ../linux-xiaomi-sheng/DEBIAN/control
PKGDIR=../linux-xiaomi-sheng
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
cat arch/arm64/boot/Image.gz arch/arm64/boot/dts/qcom/sm8550-xiaomi-sheng.dtb > Image.gz-dtb_sheng
install -Dm644 Image.gz-dtb_sheng $PKGDIR/boot/Image.gz-dtb_sheng
mv Image.gz-dtb_sheng zImage_sheng

echo "📱 正在组装 Android 刷机镜像 boot.img..."
../mkbootimg --kernel zImage_sheng --cmdline "root=PARTLABEL=linux" --base 0x00000000 --kernel_offset 0x00008000 --tags_offset 0x01e00000 --pagesize 4096 --id -o ../boot_sheng_dualboot.img
../mkbootimg --kernel zImage_sheng --cmdline "root=PARTLABEL=userdata" --base 0x00000000 --kernel_offset 0x00008000 --tags_offset 0x01e00000 --pagesize 4096 --id -o ../boot_sheng_singleboot.img

echo "🧱 安装内核模块..."
make -j$(nproc) ARCH=arm64 CC="ccache clang" LLVM=1 INSTALL_MOD_PATH=../linux-xiaomi-sheng modules_install
rm -rf ../linux-xiaomi-sheng/lib/modules/**/build
cd ..

echo "🧬 拉取固件与外设配置..."
git clone https://github.com/map220v/sheng-firmware --depth 1
mkdir -p firmware-xiaomi-sheng/usr/lib/firmware
cp -r sheng-firmware/* firmware-xiaomi-sheng/usr/lib/firmware/
rm -rf sheng-firmware

git clone https://github.com/alghiffaryfa19/alsa-sheng --depth 1
cp -r alsa-sheng/* alsa-xiaomi-sheng/
rm -rf alsa-sheng

echo "📦 正在执行 dpkg-deb 打包..."
dpkg-deb --build --root-owner-group linux-xiaomi-sheng
dpkg-deb --build --root-owner-group firmware-xiaomi-sheng
dpkg-deb --build --root-owner-group alsa-xiaomi-sheng
dpkg-deb --build --root-owner-group sheng-devauth

echo "🎉 全自动化合并与编译任务已圆满落幕！"
