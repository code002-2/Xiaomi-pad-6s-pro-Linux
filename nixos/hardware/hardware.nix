# ---
# Module: Hardware Profile (Sheng)
# Description: Board-specific hardware details and firmware loading
# Scope: Host
# ---

{ config, lib, pkgs, vars, ... }:

{
  fileSystems."/" = {
    device = "PARTLABEL=${vars.rootPartLabel}";
    fsType = "ext4";
    options = [ "noatime" "errors=remount-ro" ];
  };

  fileSystems."/mnt/vendor/persist" = {
    device = "/dev/disk/by-partlabel/persist";
    fsType = "ext4";
    options = [ "ro" "noatime" ];
  };

  zramSwap = {
    enable = true;
    algorithm = "zstd";
    memoryPercent = 25;
    priority = 100;
  };

  hardware.enableRedistributableFirmware = true;
  hardware.firmware = [ pkgs.sheng-firmware ];
  hardware.wirelessRegulatoryDatabase = true;

  environment.etc."sensors".source = "${pkgs.sheng-firmware}/etc/sensors";

  systemd.tmpfiles.rules = [
    "d /vendor 0755 root root -"
    "d /vendor/etc 0755 root root -"
    "L+ /vendor/etc/sensors - - - - /etc/sensors"
  ];

  boot.initrd.availableKernelModules = [
    "ext4"
    "phy_qcom_qmp_combo"
    "pwrseq_qcom_wcn"
    "qcom_q6v5_pas"
    "qrtr"
  ];

  boot.kernelModules = [
    "qrtr"
  ];

  systemd.services.sheng-wifi-modules = {
    description = "Load sheng Wi-Fi PCIe/MHI/ath12k modules";
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-modules-load.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      for module in pwrseq_qcom_wcn mhi mhi_pci_generic qrtr_mhi mhi_wwan_ctrl mhi_wwan_mbim mhi_net ath12k; do
        ${pkgs.kmod}/bin/modprobe "$module" || true
      done
    '';
  };

  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
  };

  systemd.services.sheng-bluetooth-modules = {
    description = "Load sheng WCN7851 Bluetooth modules";
    wantedBy = [ "bluetooth.service" ];
    before = [ "bluetooth.service" ];
    after = [ "systemd-modules-load.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      for module in bluetooth btqca hci_uart rfkill_gpio; do
        ${pkgs.kmod}/bin/modprobe "$module" || true
      done
    '';
  };

  systemd.services.sheng-touchscreen-modules = {
    description = "Load sheng Novatek touchscreen modules";
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-modules-load.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      for module in spi_qcom_geni nt36532e_spi; do
        ${pkgs.kmod}/bin/modprobe "$module" || true
      done
    '';
  };

  systemd.services.sheng-audio-modules = {
    description = "Load sheng Qualcomm audio modules";
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-modules-load.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      for module in \
        soundwire_qcom \
        snd_soc_qcom_common \
        snd_soc_qdsp6 \
        snd_soc_q6apm \
        snd_soc_q6prm \
        snd_soc_wcd938x \
        snd_soc_wcd938x_sdw \
        snd_soc_cs35l43 \
        snd_soc_cs35l43_i2c
      do
        ${pkgs.kmod}/bin/modprobe "$module" || true
      done
    '';
  };

  systemd.services.sheng-camera-modules = {
    description = "Load sheng camera/media modules";
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-modules-load.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      for module in i2c_qcom_cci qcom_camss s5kjn1_sheng ov32d40; do
        ${pkgs.kmod}/bin/modprobe "$module" || true
      done
    '';
  };

  systemd.services.sheng-led-modules = {
    description = "Load sheng LED/PWM modules";
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-modules-load.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      for module in leds_qcom_flash leds_qcom_lpg leds_pwm leds_pwm_multicolor; do
        ${pkgs.kmod}/bin/modprobe "$module" || true
      done
    '';
  };
}
