# ---
# Module: Udev Trigger Tolerant
# Description: Mobile NixOS stage-1 udev rules patch
# Scope: Patch
# ---

# Relax udevadm trigger error handling for Qualcomm platforms.
#
# Qualcomm qcom_battmgr power_supply synthetic uevent can return -EAGAIN
# (-11) during early initrd when the firmware messaging channel is not yet
# fully ready.  The upstream Mobile NixOS Tasks::UDev treats any non-zero
# exit from `udevadm trigger` as fatal, which prevents the system from
# reaching stage-2.
#
# This patch re-opens Tasks::UDev to catch a trigger failure gracefully:
# it logs the error but continues booting.  udevadm settle is still called
# and root filesystem mounting / stage-2 init failures remain fatal.

class Tasks::UDev < SingletonTask
  # Override run() to tolerate udevadm trigger failures.
  def run()
    udevd

    begin
      System.run(
        "sh", "-c",
        "out=$(udevadm trigger --action=add 2>&1); " \
        "ret=$?; " \
        "if [ $ret -ne 0 ]; then " \
        "  filtered=$(echo \"$out\" | grep -v 'qcom-battmgr' | grep -v 'Resource temporarily unavailable' || true); " \
        "  if [ -n \"$filtered\" ]; then " \
        "    echo \"$filtered\" >&2; " \
        "    exit $ret; " \
        "  fi; " \
        "  exit 0; " \
        "fi"
      )
    rescue System::CommandError => e
      $logger.warn(
        "udevadm trigger returned non-zero (#{e}); " \
        "continuing despite unrecognized errors"
      )
    end

    # settle should still run; it waits for already-queued events.
    begin
      udevadm("settle", "--timeout=30")
    rescue System::CommandError => e
      $logger.warn("udevadm settle returned non-zero (#{e}); continuing")
    end
  end
end
