#!/bin/bash
set -e

IMAGE_SIZE="8G"
FILESYSTEM_UUID="ee8d3593-59b1-480e-a3b6-4fefb17ee7d8"
DEBIAN_SUITE="trixie"
DEBIAN_MIRROR="https://mirrors.tuna.tsinghua.edu.cn/debian"

usage() {
    echo "用法: $0 <distro_name> <kernel_version>"
    exit 1
}

if [ $# -ne 2 ]; then
    usage
fi

if [ "$(id -u)" -ne 0 ]; then
    echo "请使用root权限运行"
    exit 1
fi

DISTRO=$1
KERNEL=$2
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
ROOTFS_IMG="paddeck_os_${TIMESTAMP}.img"

echo "=========================================="
echo "🎮 开始构建 PadDeck OS"
echo "内核版本: $KERNEL"
echo "=========================================="

rm -rf rootdir || true
truncate -s $IMAGE_SIZE "$ROOTFS_IMG"
mkfs.ext4 "$ROOTFS_IMG"
mkdir rootdir
mount -o loop "$ROOTFS_IMG" rootdir

debootstrap --arch=arm64 "$DEBIAN_SUITE" rootdir "$DEBIAN_MIRROR"

mount --bind /dev rootdir/dev
mount --bind /dev/pts rootdir/dev/pts
mount -t proc proc rootdir/proc
mount -t sysfs sys rootdir/sys

printf "deb %s %s main contrib non-free non-free-firmware\n" "$DEBIAN_MIRROR" "$DEBIAN_SUITE" > rootdir/etc/apt/sources.list
printf "deb %s %s-updates main contrib non-free non-free-firmware\n" "$DEBIAN_MIRROR" "$DEBIAN_SUITE" >> rootdir/etc/apt/sources.list
chroot rootdir apt update

# 🚨 精准拉取依赖：加入 Sway, Xwayland 和 Greetd
chroot rootdir apt install -y --no-install-recommends \
    systemd systemd-resolved sudo vim-tiny wget curl network-manager wpasupplicant dbus locales git 7zip unzip tar \
    libsdl2-2.0-0 libsdl2-mixer-2.0-0 libvpx9 steam-devices joystick python3-pyqt5 \
    greetd sway xwayland pipewire pipewire-pulse wireplumber \
    libgl1-mesa-dri libglx-mesa0 libegl-mesa0 mesa-vulkan-drivers mesa-utils mangohud

chroot rootdir bash -c "echo 'LANG=en_US.UTF-8' > /etc/default/locale"
chroot rootdir sed -i 's/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
chroot rootdir locale-gen en_US.UTF-8

chroot rootdir bash -c "echo -e '1234\n1234' | passwd root"
echo "paddeck-sm8550" > rootdir/etc/hostname

echo "📥 注入骁龙闭源固件..."
mkdir -p rootdir/tmp/linux-fw
git clone --depth 1 --filter=blob:none --sparse https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git rootdir/tmp/linux-fw
git -C rootdir/tmp/linux-fw sparse-checkout set qcom
mkdir -p rootdir/lib/firmware/
cp -a rootdir/tmp/linux-fw/qcom rootdir/lib/firmware/
rm -rf rootdir/tmp/linux-fw

# ================= 🚨 硬件补丁区 =================
echo "🔧 正在注入小米 Pad 6S ProWi-Fi 修复补丁..."
wget -qO rootdir/tmp/firmware-sheng-wififix.deb "https://github.com/code002-2/Xiaomi-pad-6s-pro-Linux/releases/download/fix/firmware-sheng-wififix.deb"
chroot rootdir apt install -y /tmp/firmware-sheng-wififix.deb
echo "✅ Wi-Fi 补丁安装完毕！"
# =================================================

# 创建玩家账户 (🚨已修复权限组，移除不存在的 seat 组)
chroot rootdir useradd -m -s /bin/bash luser
echo "luser:luser" | chroot rootdir chpasswd
chroot rootdir usermod -aG sudo,audio,video,render,input luser

# ================= 🚨 Steam ARM64 原生注入区 =================
echo "🚀 正在植入 Valve 官方 ARM64 Steam 客户端..."

chroot rootdir bash -c "ln -sf /usr/lib/aarch64-linux-gnu/libvpx.so.9 /usr/lib/aarch64-linux-gnu/libvpx.so.6"

mkdir -p rootdir/home/luser/.local/share/Steam/package
mkdir -p rootdir/home/luser/.local/share/Steam/compatibilitytools.d
mkdir -p rootdir/home/luser/.steam
mkdir -p rootdir/home/luser/.config/MangoHud

cat <<EOF > rootdir/home/luser/.config/MangoHud/MangoHud.conf
legacy_layout=false
horizontal
battery
gpu_stats
cpu_stats
ram
vram
fps
frametime
hud_no_margin
table_columns=14
frame_timing=1
EOF

wget -qO rootdir/tmp/steam_arm.zip https://client-update.steamstatic.com/bins_linuxarm64_linuxarm64.zip.f523fa87fc6b9b5435a5e7370cb0d664ef53b50b
unzip -q rootdir/tmp/steam_arm.zip -d rootdir/tmp/steam_arm_extracted
mv rootdir/tmp/steam_arm_extracted/steamrtarm64 rootdir/home/luser/.local/share/Steam/

echo "publicbeta" > rootdir/home/luser/.local/share/Steam/package/beta
chroot rootdir bash -c "ln -sf /home/luser/.local/share/Steam/linuxarm64 /home/luser/.steam/sdkarm64"

echo "📦 注入 Proton 11 ARM64 武器库..."
wget -qO rootdir/tmp/ARM64proton-Runtime64.tar.gz "https://github.com/code002-2/Xiaomi-pad-6s-pro-Linux/releases/download/app/ARM64proton-Runtime64.tar.gz"
tar -xzf rootdir/tmp/ARM64proton-Runtime64.tar.gz -C rootdir/home/luser/.local/share/Steam/compatibilitytools.d/

chmod -R u+rwx rootdir/home/luser/.local/share/Steam/steamrtarm64/
chroot rootdir chown -R luser:luser /home/luser/.local
chroot rootdir chown -R luser:luser /home/luser/.steam
chroot rootdir chown -R luser:luser /home/luser/.config
# ==============================================================

# ================= 🚀 OOBE 与 双轨混合容器配置区 =================
echo "🎨 正在注入 PadDeck OS 引导与 Sway 双轨容器..."

# 1. 写入 Python 激活界面脚本 (代码不变，纯 Wayland 原生运行)
cat << 'EOF' > rootdir/usr/local/bin/paddeck-oobe.py
#!/usr/bin/env python3
import sys, os, subprocess
from PyQt5.QtWidgets import (QApplication, QWidget, QVBoxLayout, QLabel, QPushButton, QListWidget, QLineEdit, QStackedWidget)
from PyQt5.QtCore import Qt

class PadDeckOOBE(QWidget):
    def __init__(self):
        super().__init__()
        self.setWindowFlags(Qt.FramelessWindowHint | Qt.WindowStaysOnTopHint)
        self.showFullScreen()
        self.setStyleSheet("background-color: #1a1a1a; color: white; font-size: 18px;")
        
        self.stack = QStackedWidget(self)
        
        # 页面 1: Wi-Fi
        self.page_wifi = QWidget()
        wifi_layout = QVBoxLayout()
        title_wifi = QLabel("连接到 Wi-Fi 网络")
        title_wifi.setAlignment(Qt.AlignCenter)
        title_wifi.setStyleSheet("font-size: 32px; font-weight: bold; margin-bottom: 20px;")
        
        self.wifi_list = QListWidget()
        self.wifi_list.setStyleSheet("background-color: #2d2d2d; border-radius: 8px; padding: 10px;")
        try:
            result = subprocess.check_output(['nmcli', '-t', '-f', 'SSID', 'dev', 'wifi']).decode('utf-8')
            ssids = list(set([line for line in result.split('\n') if line.strip()]))
            self.wifi_list.addItems(ssids)
        except:
            self.wifi_list.addItem("暂无可用网络，请稍后再试")
            
        self.pwd_input = QLineEdit()
        self.pwd_input.setPlaceholderText("请输入 Wi-Fi 密码...")
        self.pwd_input.setEchoMode(QLineEdit.Password)
        self.pwd_input.setStyleSheet("background-color: #2d2d2d; padding: 15px; border-radius: 8px;")
        
        btn_connect = QPushButton("连接并继续")
        btn_connect.setStyleSheet("background-color: #1a9fff; padding: 15px; border-radius: 8px; font-weight: bold;")
        btn_connect.clicked.connect(self.connect_wifi)
        
        wifi_layout.addWidget(title_wifi)
        wifi_layout.addWidget(self.wifi_list)
        wifi_layout.addWidget(self.pwd_input)
        wifi_layout.addWidget(btn_connect)
        self.page_wifi.setLayout(wifi_layout)
        
        # 页面 2: 欢迎
        self.page_welcome = QWidget()
        welcome_layout = QVBoxLayout()
        title_welcome = QLabel("🎉 欢迎来到 PadDeck OS")
        title_welcome.setAlignment(Qt.AlignCenter)
        title_welcome.setStyleSheet("font-size: 48px; font-weight: bold; color: #1a9fff;")
        
        subtitle = QLabel("您的骁龙 8 Gen 2 双轨掌机已准备就绪。")
        subtitle.setAlignment(Qt.AlignCenter)
        subtitle.setStyleSheet("font-size: 24px; color: #a0a0a0; margin-bottom: 40px;")
        
        btn_start = QPushButton("进入 Steam")
        btn_start.setStyleSheet("background-color: #1a9fff; padding: 20px; border-radius: 8px; font-size: 24px; font-weight: bold;")
        btn_start.clicked.connect(self.finish_oobe)
        
        welcome_layout.addStretch()
        welcome_layout.addWidget(title_welcome)
        welcome_layout.addWidget(subtitle)
        welcome_layout.addWidget(btn_start)
        welcome_layout.addStretch()
        self.page_welcome.setLayout(welcome_layout)
        
        self.stack.addWidget(self.page_wifi)
        self.stack.addWidget(self.page_welcome)
        
        main_layout = QVBoxLayout()
        main_layout.addWidget(self.stack)
        self.setLayout(main_layout)

    def connect_wifi(self):
        selected = self.wifi_list.currentItem()
        if selected:
            ssid = selected.text()
            pwd = self.pwd_input.text()
            if pwd:
                subprocess.Popen(['nmcli', 'dev', 'wifi', 'connect', ssid, 'password', pwd])
        self.stack.setCurrentIndex(1)
        
    def finish_oobe(self):
        config_dir = os.path.expanduser('~/.config')
        os.makedirs(config_dir, exist_ok=True)
        with open(os.path.join(config_dir, 'oobe_done'), 'w') as f:
            f.write("done")
        QApplication.quit()

if __name__ == '__main__':
    # OOBE 界面强制使用纯血 Wayland 运行
    os.environ['QT_QPA_PLATFORM'] = 'wayland'
    app = QApplication(sys.argv)
    ex = PadDeckOOBE()
    sys.exit(app.exec_())
EOF
chmod +x rootdir/usr/local/bin/paddeck-oobe.py

# 2. 写入极其关键的 PadDeck Session 双轨分流路由
cat << 'EOF' > rootdir/usr/local/bin/paddeck-session
#!/bin/bash
# 【环境路由策略：引导游戏走向 Wayland，拦截 Steam 走向 X11】
export SDL_VIDEODRIVER=wayland
export QT_QPA_PLATFORM=wayland
export PROTON_ENABLE_WAYLAND=1
# 防止高通 GPU 在 wlroots 下丢鼠标
export WLR_NO_HARDWARE_CURSORS=1

if [ ! -f "$HOME/.config/oobe_done" ]; then
    # 拉起原生 Wayland OOBE
    python3 /usr/local/bin/paddeck-oobe.py
fi

# 关键越狱逻辑：强制把 Steam 客户端本身的环境变量打回 X11
export GDK_BACKEND=x11
export SDL_VIDEODRIVER=x11
exec mangohud /home/luser/.local/share/Steam/steamrtarm64/steam -gamepadui -steamos3 -steampal -steamdeck
EOF
chmod +x rootdir/usr/local/bin/paddeck-session

# 3. 为 Sway 创建双轨运行容器配置
mkdir -p rootdir/home/luser/.config/sway
cat << 'EOF' > rootdir/home/luser/.config/sway/config
# PadDeck OS - Sway 容器化配置

# 显式开启 Xwayland (Steam 客户端续命的关键)
xwayland enable

# 去除所有桌面元素，营造沉浸掌机感
default_border none
default_floating_border none
bar {
    mode invisible
}
output * bg #000000 solid_color

# 自动息屏管理
exec swayidle -w timeout 600 'swaymsg "output * dpms off"' resume 'swaymsg "output * dpms on"'

# 接管权移交给分流路由脚本
exec /usr/local/bin/paddeck-session
EOF
chroot rootdir chown -R luser:luser /home/luser/.config/sway

# 4. 配置 Greetd 极简显示管理器
mkdir -p rootdir/etc/greetd
cat <<EOF > rootdir/etc/greetd/config.toml
[terminal]
vt = 1

[default_session]
command = "sway --config /home/luser/.config/sway/config"
user = "luser"
EOF
# ==============================================================

chroot rootdir bash -c "echo 'ttyMSM0' >> /etc/securetty"
ln -sf /lib/systemd/system/getty@.service rootdir/etc/systemd/system/getty.target.wants/getty@ttyMSM0.service

chroot rootdir systemctl enable systemd-resolved
ln -sf /run/systemd/resolve/stub-resolv.conf rootdir/etc/resolv.conf

mkdir -p rootdir/etc/udev/rules.d/
printf 'ENV{ID_INPUT_TOUCHSCREEN}=="1", ENV{LIBINPUT_CALIBRATION_MATRIX}="1 0 0 0 1 0 0 0 1"\n' > rootdir/etc/udev/rules.d/99-touchscreen-sheng.rules

chroot rootdir systemctl enable greetd
chroot rootdir systemctl set-default graphical.target

printf "PARTLABEL=linux / ext4 defaults,noatime,errors=remount-ro 0 1\n" > rootdir/etc/fstab

chroot rootdir apt clean
chroot rootdir rm -rf /tmp/*

umount rootdir/dev/pts || true
umount rootdir/dev || true
umount rootdir/proc || true
umount rootdir/sys || true
umount rootdir || true
rm -rf rootdir

tune2fs -U $FILESYSTEM_UUID "$ROOTFS_IMG"

echo "✅ 镜像生成完成: $ROOTFS_IMG"
7z a "paddeck_os_sm8550_${TIMESTAMP}.7z" "$ROOTFS_IMG"
rm -f "$ROOTFS_IMG"

echo "🎉 PadDeck OS (双轨混合架构版) 构建成功！"
