#!/usr/bin/env bash

# ---
# Module: Sheng Hardware Check
# Description: Diagnostic script to check hardware status on sheng
# Scope: Script
# ---
# sheng-check — Xiaomi Pad 6S Pro (sheng) hardware diagnostic script
set -uo pipefail

TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
LOGFILE="/var/log/sheng-check-${TIMESTAMP}.log"

section() {
  echo ""
  echo "══════════════════════════════════════════════"
  echo "  $1"
  echo "══════════════════════════════════════════════"
}

run_cmd() {
  echo "$ $*"
  "$@" 2>&1 || echo "(command failed or not found)"
  echo ""
}

try_cmd() {
  local cmd="$1"; shift
  if command -v "$cmd" &>/dev/null; then
    echo "$ $cmd $*"
    "$cmd" "$@" 2>&1 || true
  else
    echo "[skip] $cmd not installed"
  fi
  echo ""
}

sanitize_cmdline() {
  sed -E 's/(androidboot\.serialno=)[^ ]*/\1<REDACTED>/g'
}

sanitize_blkid() {
  sed -E 's/(UUID=")[^"]+"/\1<REDACTED>"/g; s/(PARTUUID=")[^"]+"/\1<REDACTED>"/g'
}

# Tee to both stdout and logfile
exec > >(tee -a "$LOGFILE") 2>&1

echo "sheng-check — $(date)"
echo "Log: ${LOGFILE}"

# ── Basic system ──
section "Basic System"
run_cmd uname -a
echo "$ cat /proc/cmdline (sanitized)"
cat /proc/cmdline 2>/dev/null | sanitize_cmdline
echo ""
run_cmd findmnt /
run_cmd systemctl is-system-running
run_cmd systemctl --failed --no-pager

# ── Boot timing ──
section "Boot Timing"
echo "$ systemd-analyze blame | head -50"
systemd-analyze blame 2>&1 | head -50 || true
echo ""
echo "$ systemd-analyze critical-chain"
systemd-analyze critical-chain 2>&1 || true
echo ""
echo "$ journalctl -b (timeout/failed/zram excerpts)"
journalctl -b --no-pager 2>/dev/null | grep -Ei 'timeout|timed out|start job|failed|dependency|waiting|zram|dev-zram0' | tail -200 || true
echo ""

# ── Display ──
section "Display / DRM / Backlight"
run_cmd ls -la /dev/dri
run_cmd ls -la /sys/class/drm
run_cmd ls -la /sys/class/backlight
for bl in /sys/class/backlight/*; do
  if [ -d "$bl" ]; then
    echo "Backlight: $(basename "$bl")"
    for f in brightness max_brightness bl_power; do
      [ -f "$bl/$f" ] && echo "  $f = $(cat "$bl/$f")"
    done
  fi
done
echo ""
echo "$ cat device_component/ae01000.display-controller"
cat /sys/kernel/debug/device_component/ae01000.display-controller 2>/dev/null || echo "(not available)"
echo ""
echo "$ dmesg display excerpts"
dmesg 2>/dev/null | grep -Ei 'drm|msm|dpu|dsi|panel|novatek|nt365|backlight|ktz8866' | tail -200 || true
echo ""

# ── USB / Type-C / Input ──
section "USB / Type-C / Input"
try_cmd lsusb
echo "$ find /sys/bus/usb/devices"
find /sys/bus/usb/devices -maxdepth 2 -print 2>/dev/null || true
echo ""
echo "$ find /sys/class/typec"
find /sys/class/typec -maxdepth 3 -print 2>/dev/null || true
echo ""
echo "$ find /sys/class/usb_role"
find /sys/class/usb_role -maxdepth 3 -print 2>/dev/null || true
echo ""
run_cmd ls -la /dev/input
echo "$ cat /proc/bus/input/devices"
cat /proc/bus/input/devices 2>/dev/null || true
echo ""
echo "$ dmesg usb/input excerpts"
dmesg 2>/dev/null | grep -Ei 'usb|xhci|dwc3|typec|ucsi|pmic.?glink|qrtr|hid|input|keyboard|mouse' | tail -300 || true
echo ""

# ── Touch / Keyboard ──
section "Touch / Keyboard"
try_cmd libinput list-devices
try_cmd evtest --version

# ── Network ──
section "Network"
run_cmd ip addr
try_cmd rfkill list
try_cmd nmcli device
echo "$ dmesg network excerpts"
dmesg 2>/dev/null | grep -Ei 'ath|wlan|wifi|bluetooth|bt|firmware|qcom' | tail -200 || true
echo ""

# ── Storage / Partitions ──
section "Storage / Partitions"
run_cmd lsblk -f
run_cmd df -h
echo "$ blkid (sanitized)"
blkid 2>/dev/null | sanitize_blkid || true
echo ""
run_cmd findmnt

# ── Firmware / Remoteproc ──
section "Firmware / Remoteproc"
echo "$ find /sys/class/remoteproc"
find /sys/class/remoteproc -maxdepth 2 -print 2>/dev/null || true
echo ""
echo "$ dmesg firmware excerpts"
dmesg 2>/dev/null | grep -Ei 'firmware|remoteproc|adsp|cdsp|slpi|pdr|qrtr|qcom_q6v5|pas' | tail -300 || true
echo ""

# ── Deferred Probes ──
section "Deferred Probes"
echo "$ cat /sys/kernel/debug/devices_deferred"
cat /sys/kernel/debug/devices_deferred 2>/dev/null || echo "(not available or requires root)"
echo ""

# ── Sensors / Rotation / Tablet Mode ──
section "Sensors / Rotation / Tablet Mode"
run_cmd systemctl status fake-tablet-mode.service --no-pager
run_cmd systemctl status iio-sensor-proxy.service --no-pager
run_cmd systemctl status sheng-devauth.service --no-pager
echo "$ busctl status net.hadess.SensorProxy"
busctl status net.hadess.SensorProxy 2>/dev/null || true
echo ""
echo "$ cat /sys/class/dmi/id/chassis_type"
cat /sys/class/dmi/id/chassis_type 2>/dev/null || true
echo ""
echo "$ udevadm info -e | grep -Ei 'iio|sensor|tablet|SW_TABLET_MODE'"
udevadm info -e 2>/dev/null | grep -Ei 'iio|sensor|tablet|SW_TABLET_MODE' | tail -50 || true
echo ""

# ── Power / Wakeup / Sleep ──
section "Power / Wakeup / Sleep"
run_cmd systemctl status sheng-power-key-display-toggle.service --no-pager
echo "$ cat /sys/power/mem_sleep"
cat /sys/power/mem_sleep 2>/dev/null || true
echo ""

# ── Audio / Sound ──
section "Audio / Sound"
run_cmd aplay -l
run_cmd arecord -l
echo "$ dmesg audio excerpts"
dmesg 2>/dev/null | grep -Ei 'snd|audio|wcd|lpass|codec' | tail -100 || true
echo ""

# ── Kernel Config Summary ──
section "Kernel Config Summary"
if [ -f /proc/config.gz ]; then
  echo "$ zcat /proc/config.gz key options"
  zcat /proc/config.gz 2>/dev/null | grep -E \
    'CONFIG_USB=|CONFIG_DWC3|CONFIG_TYPEC|CONFIG_UCSI|CONFIG_QCOM_PMIC_GLINK|CONFIG_HID=|CONFIG_HID_GENERIC|CONFIG_USB_HID|CONFIG_INPUT_EVDEV|CONFIG_DRM_MSM|CONFIG_BACKLIGHT_KTZ8866|CONFIG_GPIO_SHARED_PROXY|CONFIG_ZRAM' \
    || true
else
  echo "/proc/config.gz not found"
fi
echo ""

# ── Done ──
section "Done"
echo "sheng-check completed at $(date)"
echo "Full log saved to: ${LOGFILE}"
