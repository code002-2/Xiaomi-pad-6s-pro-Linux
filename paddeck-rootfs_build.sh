#!/bin/bash
set -euo pipefail

source "$(dirname "$0")/lib/rootfs-common.sh"

# --- Password configuration ---
ROOT_PASS="${ROOT_PASS:-1234}"
USER_PASS="${USER_PASS:-luser}"
USER_NAME="${USER_NAME:-luser}"


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
echo "🎮 开始构建 PadDeck OS (纯血无 GNOME / 修复转义 / 双轨掌机版)"
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

# 🚨 核心权限组件补齐 (解决 Sway 权限卡死和 USB 掉电)，绝对无 GNOME
chroot rootdir apt install -y --no-install-recommends \
    systemd systemd-resolved libpam-systemd dbus-user-session polkitd sudo vim-tiny wget curl network-manager wpasupplicant locales git 7zip unzip tar qrtr-tools \
    libsdl2-2.0-0 libsdl2-mixer-2.0-0 libvpx9 steam-devices joystick python3-pyqt5 mangohud \
    greetd sway xwayland pipewire pipewire-pulse wireplumber \
    libgl1-mesa-dri libglx-mesa0 libegl-mesa0 mesa-vulkan-drivers mesa-utils

# ================= 🚨 GitHub Actions 引号转义终极修复区 =================
echo "🌐 正在配置系统语言与基础账户..."
echo 'LANG=en_US.UTF-8' > rootdir/etc/default/locale
sed -i 's/# en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' rootdir/etc/locale.gen
chroot rootdir locale-gen en_US.UTF-8

# 弃用 passwd，改用防转义的 chpasswd
echo "root:${ROOT_PASS}" | chroot rootdir chpasswd
echo "paddeck-sm8550" > rootdir/etc/hostname
# =====================================================================

echo "📥 注入骁龙闭源固件..."
mkdir -p rootdir/tmp/linux-fw
git clone --depth 1 --filter=blob:none --sparse https://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git rootdir/tmp/linux-fw
git -C rootdir/tmp/linux-fw sparse-checkout set qcom
mkdir -p rootdir/lib/firmware/
cp -a rootdir/tmp/linux-fw/qcom rootdir/lib/firmware/
rm -rf rootdir/tmp/linux-fw

echo "🔧 注入 Wi-Fi 修复补丁..."
wget -qO rootdir/tmp/firmware-sheng-wififix.deb "https://github.com/code002-2/Xiaomi-pad-6s-pro-Linux/releases/download/fix/firmware-sheng-wififix.deb"
chroot rootdir apt install -y /tmp/firmware-sheng-wififix.deb

# 创建玩家账户并赋予护航权限组
chroot rootdir useradd -m -s /bin/bash luser
echo "${USER_NAME}:${USER_PASS}" | chroot rootdir chpasswd
chroot rootdir usermod -aG sudo,audio,video,render,input luser

echo "🚀 植入 Valve 官方 ARM64 Steam 客户端..."
chroot rootdir bash -c "ln -sf /usr/lib/aarch64-linux-gnu/libvpx.so.9 /usr/lib/aarch64-linux-gnu/libvpx.so.6"

mkdir -p rootdir/home/luser/.local/share/Steam/package
mkdir -p rootdir/home/luser/.local/share/Steam/compatibilitytools.d
mkdir -p rootdir/home/luser/.steam
mkdir -p rootdir/home/luser/.config/MangoHud

# 🚨 软件层：锁定 120Hz 渲染，防止高负载崩溃
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
fps_limit=120
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

# ================= 🚀 OOBE 与 Sway 独占混合环境注入 =================
echo "🎨 正在配置 Sway 双轨容器与 OOBE 引导..."

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
        
        self.page_welcome = QWidget()
        welcome_layout = QVBoxLayout()
        title_welcome = QLabel("🎉 欢迎来到 PadDeck OS")
        title_welcome.setAlignment(Qt.AlignCenter)
        title_welcome.setStyleSheet("font-size: 48px; font-weight: bold; color: #1a9fff;")
        subtitle = QLabel("您的骁龙 8 Gen 2 游戏掌机已准备就绪。")
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
    os.environ['QT_QPA_PLATFORM'] = 'wayland'
    app = QApplication(sys.argv)
    ex = PadDeckOOBE()
    sys.exit(app.exec_())
EOF
chmod +x rootdir/usr/local/bin/paddeck-oobe.py

cat << 'EOF' > rootdir/usr/local/bin/paddeck-session
#!/bin/bash
export SDL_VIDEODRIVER=wayland
export QT_QPA_PLATFORM=wayland
export PROTON_ENABLE_WAYLAND=1
# 高通防光标崩溃
export WLR_NO_HARDWARE_CURSORS=1

if [ ! -f "$HOME/.config/oobe_done" ]; then
    python3 /usr/local/bin/paddeck-oobe.py
fi

# Steam 客户端打回 Xwayland 保命
export GDK_BACKEND=x11
export SDL_VIDEODRIVER=x11
exec mangohud /home/luser/.local/share/Steam/steamrtarm64/steam -gamepadui -steamos3 -steampal -steamdeck
EOF
chmod +x rootdir/usr/local/bin/paddeck-session

mkdir -p rootdir/home/luser/.config/sway
cat << 'EOF' > rootdir/home/luser/.config/sway/config
xwayland enable
default_border none
default_floating_border none
bar {
    mode invisible
}
# 🚨 物理层：强制锁定 120Hz 防驱动崩溃 (适配小米 Pad 6S Pro)
output * mode 3048x2032@120Hz bg #000000 solid_color

exec swayidle -w timeout 600 'swaymsg "output * dpms off"' resume 'swaymsg "output * dpms on"'
exec /usr/local/bin/paddeck-session
EOF
chroot rootdir chown -R luser:luser /home/luser/.config/sway

# 配置 Greetd 极简显示管理器 (接管登录)
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

# 启用 Greetd 接管开机
chroot rootdir systemctl enable greetd
chroot rootdir systemctl set-default graphical.target

# 🚨 使用你验证过的 PARTLABEL 挂载方式
printf "PARTLABEL=linux / ext4 defaults,noatime,errors=remount-ro 0 1\n" > rootdir/etc/fstab

chroot rootdir apt clean
chroot rootdir rm -rf /tmp/*

echo "🧹 正在清理后台遗留进程并安全卸载挂载点..."
fuser -k -9 -m rootdir || true
sleep 2

umount -l rootdir/dev/pts || true
umount -l rootdir/dev || true
umount -l rootdir/proc || true
umount -l rootdir/sys || true
umount -l rootdir || true
sleep 2

rm -rf rootdir
tune2fs -U $FILESYSTEM_UUID "$ROOTFS_IMG"

echo "✅ 原始镜像生成完成: $ROOTFS_IMG"
SPARSE_IMG="sparse_${ROOTFS_IMG}"
# 🚨 img2simg 转换，保证 Fastboot 完美刷入
img2simg "$ROOTFS_IMG" "$SPARSE_IMG"

echo "🗜️ 正在生成最终 7z 压缩包 (极速模式)..."
7z a -mx=1 "paddeck_os_sm8550_${TIMESTAMP}.7z" "$SPARSE_IMG"
rm -f "$ROOTFS_IMG" "$SPARSE_IMG"

echo "🎉 Fastboot 专用 PadDeck OS (最终绝杀版) 构建成功！"
