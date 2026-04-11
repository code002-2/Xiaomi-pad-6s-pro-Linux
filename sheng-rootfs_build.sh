set -e

IMAGE_SIZE="8G"
FILESYSTEM_UUID="ee8d3593-59b1-480e-a3b6-4fefb17ee7d8"

if [ $# -lt 2 ]; then
    echo "Usage: $0 <distro-variant> <kernel>"
    exit 1
fi

if [ "$(id -u)" -ne 0 ]; then
    echo "Run as root"
    exit 1
fi

DISTRO=$1
KERNEL=$2

distro_type=$(echo "$DISTRO" | cut -d'-' -f1)
distro_variant=$(echo "$DISTRO" | cut -d'-' -f2)

if [ "$distro_type" != "debian" ]; then
    echo "Only debian supported"
    exit 1
fi

distro_version="forky"

TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

# 🔥 MULTI FLAVOUR
FLAVOURS=("lomiri" "gnome")

for FLAVOUR in "${FLAVOURS[@]}"; do

echo ""
echo "======================================"
echo "🚀 BUILD: $FLAVOUR"
echo "======================================"

ROOTFS_IMG="${distro_type}_${distro_version}_${FLAVOUR}_${TIMESTAMP}.img"

# Cleanup
rm -rf rootdir || true

# Create image
truncate -s $IMAGE_SIZE "$ROOTFS_IMG"
mkfs.ext4 "$ROOTFS_IMG"

mkdir rootdir
mount -o loop "$ROOTFS_IMG" rootdir

# Bootstrap
debootstrap --arch=arm64 "$distro_version" rootdir http://deb.debian.org/debian/

# Mount
mount --bind /dev rootdir/dev
mount --bind /dev/pts rootdir/dev/pts
mount -t proc proc rootdir/proc
mount -t sysfs sys rootdir/sys

# Base system
chroot rootdir apt update
chroot rootdir apt install -y \
    systemd sudo vim wget curl \
    network-manager openssh-server \
    wpasupplicant dbus

# Root password
chroot rootdir bash -c "echo -e '1234\n1234' | passwd root"

# Host
echo "xiaomi-sheng" > rootdir/etc/hostname

# =========================
# 🖥️ DESKTOP
# =========================
if [ "$distro_variant" = "desktop" ]; then

    echo "🎨 Installing flavour: $FLAVOUR"

    if [ "$FLAVOUR" = "lomiri" ]; then

        chroot rootdir apt install -y \
            lomiri lomiri-desktop-session lomiri-system-settings \
            lightdm lightdm-gtk-greeter firefox-esr

        chroot rootdir systemctl disable gdm3 2>/dev/null || true
        chroot rootdir systemctl disable gdm 2>/dev/null || true
        chroot rootdir systemctl enable lightdm

        SESSION="lomiri"

    elif [ "$FLAVOUR" = "gnome" ]; then

        chroot rootdir apt install -y \
            gnome-shell gnome-session gdm3 firefox-esr

        chroot rootdir systemctl enable gdm3

        SESSION="gnome"

    fi

    # User
    chroot rootdir useradd -m -s /bin/bash luser
    echo "luser:luser" | chroot rootdir chpasswd
    chroot rootdir usermod -aG sudo luser

    # Autologin
    if [ "$FLAVOUR" = "lomiri" ]; then
        mkdir -p rootdir/etc/lightdm/lightdm.conf.d
        cat > rootdir/etc/lightdm/lightdm.conf.d/50-autologin.conf <<EOF
[Seat:*]
autologin-user=luser
autologin-user-timeout=0
user-session=lomiri
greeter-session=lightdm-gtk-greeter
EOF

    elif [ "$FLAVOUR" = "gnome" ]; then
        mkdir -p rootdir/etc/gdm3
        cat > rootdir/etc/gdm3/daemon.conf <<EOF
[daemon]
AutomaticLoginEnable=true
AutomaticLogin=luser
EOF
    fi

    chroot rootdir systemctl enable NetworkManager
    chroot rootdir systemctl set-default graphical.target

fi

# fstab
echo "PARTLABEL=linux / ext4 defaults 0 1" > rootdir/etc/fstab

# Clean
chroot rootdir apt clean

# Unmount
umount rootdir/dev/pts || true
umount rootdir/dev || true
umount rootdir/proc || true
umount rootdir/sys || true
umount rootdir || true

rm -rf rootdir

# UUID
tune2fs -U $FILESYSTEM_UUID "$ROOTFS_IMG"

echo "✅ DONE: $ROOTFS_IMG"

done