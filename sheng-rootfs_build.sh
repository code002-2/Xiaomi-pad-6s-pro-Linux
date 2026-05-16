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

distro_version="trixie"

TIMESTAMP=$(date +"%Y%m%d_%H%M%S")

# 🔥 MULTI FLAVOUR
FLAVOURS=("gnome")
BOOTMODES=("dual")

for FLAVOUR in "${FLAVOURS[@]}"; do
for MODE in "${BOOTMODES[@]}"; do

echo ""
echo "======================================"
echo "🚀 BUILD: $FLAVOUR - $MODE"
echo "======================================"

ROOTFS_IMG="${distro_type}_${distro_version}_${FLAVOUR}_${MODE}_${TIMESTAMP}.img"

rm -rf rootdir || true

truncate -s $IMAGE_SIZE "$ROOTFS_IMG"
mkfs.ext4 "$ROOTFS_IMG"

mkdir rootdir
mount -o loop "$ROOTFS_IMG" rootdir

# bootstrap
debootstrap --arch=arm64 "$distro_version" rootdir http://deb.debian.org/debian/

# mount
mount --bind /dev rootdir/dev
mount --bind /dev/pts rootdir/dev/pts
mount -t proc proc rootdir/proc
mount -t sysfs sys rootdir/sys

# base packages
chroot rootdir apt update
chroot rootdir apt install -y \
    systemd sudo vim wget curl \
    network-manager openssh-server \
    wpasupplicant dbus

echo "📦 Installing device-specific .deb packages..."

# Copy semua .deb ke rootfs
cp *.deb rootdir/tmp/

# Install dependency dulu (biar aman)
chroot rootdir apt install -y \
    libglib2.0-0 \
    libprotobuf-c1 \
    libqmi-glib5 \
    libmbim-glib4 || true

# Install satu per satu (biar gampang debug kalau gagal)
# debug
ls -lah rootdir/tmp/

chroot rootdir bash -c "apt update && apt install -y /tmp/*.deb" || exit 1

echo "✅ All custom .deb installed"

# root password
chroot rootdir bash -c "echo -e '1234\n1234' | passwd root"

echo "xiaomi-$FLAVOUR-$MODE" > rootdir/etc/hostname

# =========================
# 🖥️ DESKTOP
# =========================
if [ "$distro_variant" = "desktop" ]; then

    if [ "$FLAVOUR" = "lomiri" ]; then
        chroot rootdir apt install -y \
            lomiri lomiri-desktop-session lomiri-system-settings \
            lightdm lightdm-gtk-greeter firefox-esr

        chroot rootdir systemctl disable gdm3 2>/dev/null || true
        chroot rootdir systemctl enable lightdm

    elif [ "$FLAVOUR" = "gnome" ]; then
        chroot rootdir apt install -y \
            gnome-shell gnome-session gnome-terminal gdm3 firefox-esr

        chroot rootdir systemctl enable gdm3
    fi

    # user
    chroot rootdir useradd -m -s /bin/bash luser
    echo "luser:luser" | chroot rootdir chpasswd
    chroot rootdir usermod -aG sudo luser

    # autologin
    if [ "$FLAVOUR" = "lomiri" ]; then
        mkdir -p rootdir/etc/lightdm/lightdm.conf.d
        cat > rootdir/etc/lightdm/lightdm.conf.d/50-autologin.conf <<EOF
[Seat:*]
autologin-user=luser
autologin-user-timeout=0
user-session=lomiri
greeter-session=lightdm-gtk-greeter
EOF

    else
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

# =========================
# 💽 FSTAB (INI KUNCI)
# =========================

if [ "$MODE" = "dual" ]; then
    echo "PARTLABEL=linux / ext4 defaults 0 1" > rootdir/etc/fstab
else
    echo "PARTLABEL=userdata / ext4 defaults 0 1" > rootdir/etc/fstab
fi

# clean
chroot rootdir apt clean

# unmount
umount rootdir/dev/pts || true
umount rootdir/dev || true
umount rootdir/proc || true
umount rootdir/sys || true
umount rootdir || true

rm -rf rootdir

# uuid
tune2fs -U $FILESYSTEM_UUID "$ROOTFS_IMG"

echo "✅ DONE: $ROOTFS_IMG"

# compress
echo "🗜️ compressing..."
7z a "${ROOTFS_IMG}.7z" "$ROOTFS_IMG"

done
done
