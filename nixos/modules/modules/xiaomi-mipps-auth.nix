# ---
# Module: Xiaomi MIPPS Auth Service
# Description: Systemd service for Xiaomi MIPPS authentication
# Scope: Service
# ---

{ config, lib, pkgs, ... }:

let
  cfg = config.services.xiaomi-mipps-auth;
  package = pkgs.callPackage ../packages/xiaomi-mipps-auth.nix { };
  retryPackage = pkgs.writeShellApplication {
    name = "xiaomi-mipps-auth-retry";
    runtimeInputs = [
      package
      pkgs.coreutils
      pkgs.gnugrep
    ];
    text = ''
      set -u

      find_xiaomi_dir() {
        for path in /sys/class/qcom-battery /sys/devices/platform/pmic-glink/*/xiaomi; do
          [ -e "$path/request_vdm_cmd" ] || continue
          printf '%s\n' "$path"
          return 0
        done
        return 1
      }

      read_node() {
        local root="$1"
        local name="$2"
        [ -e "$root/$name" ] || return 1
        tr -d '\000' < "$root/$name" 2>/dev/null || return 1
      }

      is_complete() {
        local root="$1"
        [ "$(read_node "$root" pd_verifed 2>/dev/null || true)" = "1" ] \
          && [ "$(read_node "$root" fastchg_mode 2>/dev/null || true)" = "1" ]
      }

      is_xiaomi_svid() {
        case "$1" in
          0x2717|2717|10007) return 0 ;;
          *) return 1 ;;
        esac
      }

      is_empty_svid() {
        case "''${1:-}" in
          ""|0|0000|0x0000) return 0 ;;
          *) return 1 ;;
        esac
      }

      root="$(find_xiaomi_dir || true)"
      if [ -z "$root" ]; then
        echo "MiPPS auth skipped: request_vdm_cmd sysfs node not found"
        exit 0
      fi

      max_attempts=10
      sleep_seconds=1

      for attempt in $(seq 1 "$max_attempts"); do
        if is_complete "$root"; then
          echo "MiPPS auth already active before attempt $attempt"
          xiaomi-mipps-auth --sysfs "$root" --timeout 3 || true
          exit 0
        fi

        real_type="$(read_node "$root" real_type 2>/dev/null || true)"
        adapter_svid="$(read_node "$root" adapter_svid 2>/dev/null || true)"
        pdo2="$(read_node "$root" pdo2 2>/dev/null || true)"
        echo "MiPPS auth attempt $attempt/$max_attempts: real_type=''${real_type:-unknown} adapter_svid=''${adapter_svid:-unknown} pdo2=''${pdo2:-unknown}"

        # xiaomi-mipps-auth performs Type-C attach/role nudging before checking
        # the Xiaomi SVID. Do not wait for adapter_svid here, because on sheng
        # that can leave the charger stuck as SDP/generic PD forever.
        xiaomi-mipps-auth --sysfs "$root" --timeout 3 || true

        if is_complete "$root"; then
          echo "MiPPS auth active after attempt $attempt"
          exit 0
        fi

        adapter_svid="$(read_node "$root" adapter_svid 2>/dev/null || true)"
        if ! is_xiaomi_svid "$adapter_svid"; then
          if is_empty_svid "$adapter_svid"; then
            sleep "$sleep_seconds"
            continue
          fi
          echo "MiPPS auth skipped: non-Xiaomi adapter_svid=$adapter_svid"
          exit 0
        fi

        sleep "$sleep_seconds"
      done

      echo "MiPPS auth did not become active after $max_attempts attempts"
      echo "Final status:"
      for name in real_type adapter_svid pdo2 apdo_max power_max fastchg_mode pd_verifed request_vdm_cmd; do
        [ -e "$root/$name" ] || continue
        printf '%s=' "$name"
        read_node "$root" "$name" || true
      done
      exit 0
    '';
  };
in
{
  options.services.xiaomi-mipps-auth.enable =
    lib.mkEnableOption "Xiaomi MiPPS/PPS charger authentication";

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      package
      retryPackage
    ];

    systemd.services.xiaomi-mipps-auth = {
      description = "Xiaomi MiPPS/PPS charger authentication";
      unitConfig.ConditionPathExistsGlob =
        "/sys/devices/platform/pmic-glink/*/xiaomi/request_vdm_cmd";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = "${pkgs.util-linux}/bin/flock -n -E 0 /run/xiaomi-mipps-auth.lock ${retryPackage}/bin/xiaomi-mipps-auth-retry";
        TimeoutStartSec = 45;
      };
    };

    services.udev.extraRules = ''
      # Delegate Xiaomi MiPPS authentication to systemd after a USB-C partner attaches.
      ACTION=="add", SUBSYSTEM=="typec", KERNEL=="port*-partner", TAG+="systemd", ENV{SYSTEMD_WANTS}+="xiaomi-mipps-auth.service"
      # Some adapters expose their Xiaomi SVID/PDOs only after the USB power_supply
      # node changes from SDP/unknown to PD/PPS. Retry when that state changes.
      ACTION=="change", SUBSYSTEM=="power_supply", KERNEL=="qcom-battmgr-usb", ATTR{online}=="1", TAG+="systemd", ENV{SYSTEMD_WANTS}+="xiaomi-mipps-auth.service"
    '';
  };
}
