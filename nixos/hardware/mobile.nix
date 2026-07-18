# ---
# Module: Mobile NixOS Base
# Description: Mobile NixOS specific hacks and stage-1 settings
# Scope: System
# ---

{ config, lib, pkgs, vars, ... }:

let
  headlessStage1Task = pkgs.writeTextDir "zz-sheng-headless-stage1.rb" (
    (builtins.readFile ../patches/stage-1-headless-no-gui.rb)
    + "\n"
    + (builtins.readFile ../patches/stage-1-headless-generation-menu.rb)
  );
  udevTolerantTask = pkgs.writeTextDir "zz-sheng-udev-tolerant.rb" (
    builtins.readFile ../patches/stage-1-udev-trigger-tolerant.rb
  );
  stage1Firmware = pkgs.runCommand "sheng-stage1-firmware" { } ''
    mkdir -p $out/lib/firmware
    cp -r ${pkgs.sheng-firmware}/lib/firmware/qcom $out/lib/firmware/
  '';
  closureInfo = pkgs.buildPackages.closureInfo {
    rootPaths = config.system.build.toplevel;
  };
  kernelModulesTree = pkgs.runCommand "sheng-kernel-modules-tree" {
    nativeBuildInputs = [
      pkgs.buildPackages.kmod
    ];
  } ''
    mkdir -p $out/lib
    cp -r ${config.mobile.boot.stage-1.kernel.package}/lib/modules $out/lib/
    chmod -R u+w $out/lib/modules

    version="$(basename "$out"/lib/modules/*)"
    depmod -b "$out" "$version"
  '';
  udevadmWrapper = pkgs.writeShellScript "udevadm-trigger-wrapper" ''
    out=$(${config.systemd.package}/bin/udevadm trigger "$@" 2>&1)
    ret=$?
    
    if [ $ret -ne 0 ]; then
      filtered=$(echo "$out" | grep -v 'qcom-battmgr' | grep -v 'Resource temporarily unavailable' || true)
      if [ -n "$filtered" ]; then
        echo "$filtered" >&2
        exit $ret
      fi
      exit 0
    fi
  '';
in
{
  mobile.enable = true;

  mobile.generatedFilesystems.rootfs = lib.mkForce {
    name = "nixos-sheng-rootfs";
    filesystem = "ext4";
    label = "linux";
    ext4.partitionID = "ee8d3593-59b1-480e-a3b6-4fefb17ee7d8";
    location = "/rootfs.img";
    extraPadding = 1024 * 1024 * 1024;

    # Keep this aligned with Mobile NixOS' default rootfs.nix populate logic.
    populateCommands = ''
      mkdir -p ./nix/store
      echo "Copying system closure..."

      err=0
      while IFS= read -r path; do
        echo "  Copying $path"
        if test -e "$path"; then
          cp -prf "$path" ./nix/store
        else
          2>&1 printf "ERROR: path %q does not exist...\n" "$path"
          (( ++err ))
        fi
      done < "${closureInfo}/store-paths"

      if (( err > 0 )); then
        2>&1 printf "... Bailing out, %d errors.\n" "$err"
        exit 2
      fi

      echo "Done copying system closure..."
      cp -v ${closureInfo}/registration ./nix-path-registration

      echo "Creating system profile..."
      mkdir -p ./nix/var/nix/profiles
      ln -s ${config.system.build.toplevel} ./nix/var/nix/profiles/system-1-link
      ln -s system-1-link ./nix/var/nix/profiles/system

      echo "Injecting sheng-firmware into /lib/firmware..."
      mkdir -p ./lib/firmware
      cp -r ${pkgs.sheng-firmware}/lib/firmware/* ./lib/firmware/
      cp -r ${pkgs.wireless-regdb}/lib/firmware/* ./lib/firmware/

      echo "Injecting kernel modules into /lib/modules..."
      if [ -d ${kernelModulesTree}/lib/modules ]; then
        mkdir -p ./lib/modules
        cp -r ${kernelModulesTree}/lib/modules/* ./lib/modules/
      else
        echo "WARNING: sheng kernel modules tree has no lib/modules directory"
      fi
    '';

    additionalCommands = ''
      echo ":: Adding hydra-build-products"
      (PS4=" $ "; set -x
      mkdir -p $out_path/nix-support
      cat <<EOF > $out_path/nix-support/hydra-build-products
      file rootfs $img
      EOF
      )
    '';
  };

  fileSystems."/" = lib.mkForce {
    device = "/dev/disk/by-partlabel/${vars.rootPartLabel}";
    fsType = "ext4";
    neededForBoot = true;
    autoResize = false;
    options = [ "noatime" ];
  };

  mobile.boot.stage-1 = {
    compression = "gzip";
    crashToBootloader = false;

    bootConfig = {
      log.level = "DEBUG";
      boot.fail.shell = true;
      gui.enable = false;
      splash.disabled = true;
      sheng_generation_menu = {
        enable = true;
        timeout = 30;
      };
    };

    gui.enable = false;

    tasks = [
      headlessStage1Task
      udevTolerantTask
    ];

    extraUtils = [
      pkgs.kbd
    ];

    shell.shellOnFail = true;

    kernel.modules = [ ];
    kernel.additionalModules = [ ];
    # Keep large device firmware in rootfs. Stage-1 only needs Qualcomm boot
    # firmware; including the full package makes boot.img exceed boot_b.
    firmware = [ stage1Firmware ];
  };

  mobile.boot.stage-1.fail.reboot = false;

  mobile.adbd.enable = lib.mkDefault true;

  mobile.beautification.silentBoot = lib.mkForce false;

  system.modulesTree = lib.mkForce [
    kernelModulesTree
  ];

  documentation.enable = false;

  # Wrap udevadm trigger in stage-2 to prevent qcom-battmgr from polluting the journal with fatal errors
  systemd.services.systemd-udev-trigger.serviceConfig.ExecStart = lib.mkForce [
    ""
    "${udevadmWrapper} --type=subsystems --action=add"
    "${udevadmWrapper} --type=devices --action=add"
  ];
}
