# ---
# Module: System Configuration
# Description: Overall system configuration for the device
# Scope: System
# ---

{ config, pkgs, lib, vars, ... }:

{
  imports = [
    ./hardware/hardware.nix
    ./modules/sheng-devauth.nix
    ./modules/xiaomi-mipps-auth.nix
  ];

  nixpkgs.hostPlatform = "aarch64-linux";

  system.stateVersion = "25.11";

  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];

  networking.hostName = lib.mkDefault "nixos-sheng";
  networking.networkmanager = {
    enable = true;
    # Managing the P2P device can leave WCN7850 scans stuck after Wi-Fi is
    # toggled, making every 5 GHz BSS disappear until the driver is reloaded.
    unmanaged = [ "interface-name:p2p-dev-wlp1s0" ];
  };
  networking.useDHCP = lib.mkDefault true;

  time.timeZone = lib.mkDefault "Asia/Shanghai";
  services.timesyncd = {
    enable = lib.mkDefault true;
    servers = lib.mkDefault [
      "ntp.aliyun.com"
      "cn.pool.ntp.org"
      "time.cloudflare.com"
    ];
  };
  i18n.defaultLocale = lib.mkDefault "en_US.UTF-8";

  # Bring-up hacks removed for better security
  # security.sudo.wheelNeedsPassword = false;

  services.openssh.enable = lib.mkDefault true;

  services.getty = {
    helpLine = ''
      NixOS sheng debug console
      Useful checks: dmesg -w, journalctl -b, ip addr, lsmod
    '';
  };

  # Suspend currently times out in the sheng kernel. Ignoring short power-key
  # presses prevents GDM/logind from disconnecting the device for about 40s.
  services.logind.settings.Login.HandlePowerKey = "ignore";
  # 盖板事件由 fake-tablet-mode 服务直接处理（D-Bus 息屏），logind 不介入。
  services.logind.settings.Login.HandleLidSwitch = "ignore";
  services.logind.settings.Login.HandleLidSwitchExternalPower = "ignore";
  services.logind.settings.Login.HandleLidSwitchDocked = "ignore";

  # 彻底禁用 suspend 功能，防止 GNOME 界面出现休眠按钮，避免误触导致设备内核假死
  systemd.sleep.settings = {
    Sleep = {
      AllowSuspend = "no";
      AllowHibernation = "no";
      AllowHybridSleep = "no";
      AllowSuspendThenHibernate = "no";
    };
  };

  services.xiaomi-mipps-auth.enable = true;

  console = {
    earlySetup = true;
    font = "Lat2-Terminus16";
    keyMap = "us";
  };

  services.kmscon = {
    enable = true;
    config = {
      hwaccel = false;
      "font-size" = 18;
    };
  };

  environment.systemPackages = let
    sheng-check = pkgs.writeShellScriptBin "sheng-check" (
      builtins.readFile ./scripts/sheng-check.sh
    );
    sheng-reboot-generation-menu = pkgs.writeShellScriptBin "sheng-reboot-generation-menu" ''
      set -eu

      if [ "$(id -u)" -ne 0 ]; then
        echo "Run this command with sudo." >&2
        exit 1
      fi

      install -d -m 0755 /var/lib/sheng-boot-menu
      : > /var/lib/sheng-boot-menu/requested
      sync
      systemctl reboot
    '';
  in with pkgs; [
    sheng-check
    sheng-reboot-generation-menu
    alsa-ucm-conf
    alsa-utils
    e2fsprogs
    bluez
    iio-sensor-proxy
    kmod
    libssc
    libinput
    util-linux
    gitMinimal # Required for nixos-rebuild to process git+file:// flakes via sudo
    wf-recorder
  ];

  environment.variables.ALSA_CONFIG_UCM2 = "/run/current-system/sw/share/alsa/ucm2";
  systemd.user.settings.Manager.DefaultEnvironment =
    "ALSA_CONFIG_UCM2=/run/current-system/sw/share/alsa/ucm2";

  systemd.packages = [ pkgs.iio-sensor-proxy ];
  services.dbus.packages = [ pkgs.iio-sensor-proxy ];
  services.udev.packages = [ pkgs.iio-sensor-proxy ];

  systemd.services.iio-sensor-proxy.wantedBy = [ "multi-user.target" ];

  services.udev.extraRules = ''
    ENV{ID_INPUT_TOUCHSCREEN}=="1", ENV{LIBINPUT_CALIBRATION_MATRIX}="1 0 0 0 1 0 0 0 1", ENV{ID_INPUT_TOUCHSCREEN_INTEGRATION}="internal"
    SUBSYSTEM=="block", ENV{DEVTYPE}=="partition", ENV{ID_PATH}=="platform-1d84000.ufshc-scsi-*", ENV{UDISKS_IGNORE}="1"
  '';

  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    pulse.enable = true;
  };

  boot.loader.grub.enable = false;
  boot.loader.generic-extlinux-compatible.enable = false;
  boot.extraModprobeConfig = ''
    options cfg80211 ieee80211_regdom=CN
  '';

  boot.kernelParams = [
    "console=tty0"
    "console=ttyMSM0,115200n8"
    "root=PARTLABEL=${vars.rootPartLabel}"
    "rootwait"
    "logo.nologo"
    "systemd.show_status=true"
    "udev.log_level=info"
    "rd.udev.log_level=info"
    "vt.global_cursor_default=1"
    "androidboot.force_normal_boot=1"
  ];

  boot.consoleLogLevel = 7;
  boot.initrd.verbose = true;

  boot.supportedFilesystems = [ "ext4" ];

  # Disable default xterm
  services.xserver.desktopManager.xterm.enable = false;
}
