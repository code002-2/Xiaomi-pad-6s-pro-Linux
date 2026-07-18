# ---
# Module: Device Entry (Sheng)
# Description: Device specific hardware configuration
# Scope: Host
# ---

{ config, lib, pkgs, ... }:

let
  cfg = config.mobile.hardware.socs."qualcomm-sm8550";
in
{
  imports = [
    ./sensors
  ];

  options.mobile.hardware.socs."qualcomm-sm8550".enable = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = "Enable when SOC is Qualcomm SM8550.";
  };

  config = lib.mkMerge [
    {
      mobile.device = {
        name = "xiaomi-sheng";
        identity = {
          name = "Xiaomi Pad 6S Pro";
          manufacturer = "Xiaomi";
        };
        supportLevel = "best-effort";
      };

      mobile.hardware = {
        soc = "qualcomm-sm8550";
        ram = 1024 * 8;
        screen = {
          width = 3048;
          height = 2032;
        };
      };

      mobile.boot.stage-1.kernel = {
        package = pkgs.callPackage ./kernel { };
        modular = true;
        allowMissingModules = true;
      };

      mobile.system.type = "android";
      mobile.system.android = {
        ab_partitions = true;
        boot_as_recovery = false;
        has_recovery_partition = false;
        boot_partition_destination = "boot";
        system_partition_destination = "linux";
        device_name = "sheng";

        bootimg.flash = {
          offset_base = "0x00000000";
          offset_kernel = "0x00008000";
          offset_ramdisk = "0x01000000";
          offset_second = "0x00000000";
          offset_tags = "0x01e00000";
          pagesize = "4096";
        };

        appendDTB = [
          "dtbs/qcom/sm8550-xiaomi-sheng.dtb"
        ];
      };

      mobile.usb = {
        mode = "gadgetfs";
        idVendor = "18D1";
        idProduct = "D001";
        gadgetfs.functions = {
          adb = "ffs.adb";
          rndis = "rndis.usb0";
          mass_storage = "mass_storage.0";
        };
      };
    }

    (lib.mkIf cfg.enable {
      mobile.system.system = "aarch64-linux";
      mobile.kernel.structuredConfig = [
        (helpers: with helpers; {
          ARCH_QCOM = lib.mkDefault yes;
        })
      ];
    })
  ];
}
