{ config, lib, pkgs, ... }:

let
  myDebPackages = [
    # 0. 基础 Mesa 驱动
    (pkgs.fetchurl {
      url = "http://ftp.br.debian.org/debian/pool/main/m/mesa/mesa-common-dev_26.0.7-1_arm64.deb";
      sha256 = "sha256-bqy5ClZAfZRj6N5hUfDnIUdDhPq2GeL82dGK0sQh7Z4="; 
    })
    # 1. 核心内核与模块
    (pkgs.fetchurl {
      url = "https://github.com/code002-2/Xiaomi-pad-6s-pro-Linux/releases/download/kernel-bundle-7.0/linux-xiaomi-sheng.deb";
      sha256 = "sha256-+iI1Roq7+myK7M6wCvFFyfaS03ik5u95r/O2ZRzk5Nc="; 
    })
    # 2. 核心固件包
    (pkgs.fetchurl {
      url = "https://github.com/code002-2/Xiaomi-pad-6s-pro-Linux/releases/download/kernel-bundle-7.0/firmware-xiaomi-sheng.deb";
      sha256 = "sha256-VdN93sVEMdPD0Zl/8UCWQOEo17IjM3CFgLyZm42muOk="; 
    })
    # 3. 音频驱动 (ALSA)
    (pkgs.fetchurl {
      url = "https://github.com/code002-2/Xiaomi-pad-6s-pro-Linux/releases/download/kernel-bundle-7.0/alsa-xiaomi-sheng.deb";
      sha256 = "sha256-qlWfcYSIlgZT6ymwCNToPes30PStzmr5ZvvEl7ShObo="; 
    })
    # 4. 高通 FastRPC (DSP 通讯层)
    (pkgs.fetchurl {
      url = "https://github.com/code002-2/Xiaomi-pad-6s-pro-Linux/releases/download/kernel-bundle-7.0/fastrpc_1.0.2-1_arm64.deb";
      sha256 = "sha256-al0ggsBaN4qpImNBynIEpvHhRsvcUZk0m3GT8s5aJd4="; 
    })
    # 5. IIO 传感器代理
    (pkgs.fetchurl {
      url = "https://github.com/code002-2/Xiaomi-pad-6s-pro-Linux/releases/download/kernel-bundle-7.0/iio-sensor-proxy_99993.8-6_arm64.deb";
      sha256 = "sha256-U5YrqZhF5cHxuN4INjqGAZoTPRnY8/Ujx5JrR+KkZzM="; 
    })
    # 6. 高通 SSC 传感器库
    (pkgs.fetchurl {
      url = "https://github.com/code002-2/Xiaomi-pad-6s-pro-Linux/releases/download/kernel-bundle-7.0/libssc_0.4.2-1_arm64.deb";
      sha256 = "sha256-jpe+l3X+Aya00JCmDAiNnSLoSUG0xhhl8aZiM53gJj0="; 
    })
    # 7. Sheng 专属传感器配置
    (pkgs.fetchurl {
      url = "https://github.com/code002-2/Xiaomi-pad-6s-pro-Linux/releases/download/kernel-bundle-7.0/sheng-sensors_20240917-1_arm64.deb";
      sha256 = "sha256-9T6i7D/9GOkoWpkt3Tc746RzYzRuFTPwHtb31cefPSA="; 
    })
    # 8. 设备认证/授权模块
    (pkgs.fetchurl {
      url = "https://github.com/code002-2/Xiaomi-pad-6s-pro-Linux/releases/download/kernel-bundle-7.0/sheng-devauth.deb";
      sha256 = "sha256-S978BNUFbBEczJ2m936tRH2Q4jVRaII8Xpr5c9/orD0="; 
    })
  ];

  shengFirmwareAndModules = pkgs.stdenv.mkDerivation {
    pname = "sheng-firmware-modules";
    version = "7.0.0-sm8550";

    nativeBuildInputs = [ pkgs.dpkg ];
    unpackPhase = "true";

    installPhase = ''
      mkdir -p $out

      echo "📦 开始批量提取所有的 .deb 包..."
      for pkg in ${lib.concatStringsSep " " myDebPackages}; do
        echo "   -> 正在提取 $pkg"
        dpkg-deb -x $pkg $out/
      done

      echo "⚙️ 修复高通 WiFi 固件 (board-2.bin 伪装)..."
      FW_DIR="$out/lib/firmware/ath12k/WCN7850/hw2.0"
      if [ -f "$FW_DIR/board-2.bin" ]; then
          cp "$FW_DIR/board-2.bin" "$FW_DIR/board.bin"
      fi

      echo "🔧 修复内核驱动目录名称..."
      MOD_DIR="$out/lib/modules"
      TARGET_VER="7.0.0-sm8550-gf273227fab85"
      if [ -d "$MOD_DIR" ]; then
          for dir in "$MOD_DIR"/*; do
              if [ -d "$dir" ] && [ "$(basename "$dir")" != "$TARGET_VER" ]; then
                  mv "$dir" "$MOD_DIR/$TARGET_VER"
                  break
              fi
          done
      fi
    '';
  };
in
{
  hardware.firmware = [ shengFirmwareAndModules ];
  boot.extraModulePackages = [ shengFirmwareAndModules ];

  fileSystems."/" = {
    device = "/dev/disk/by-partlabel/linux";
    fsType = "ext4";
    options = [ "defaults" "noatime" "errors=remount-ro" ];
  };
  fileSystems."/boot" = {
    device = "/dev/disk/by-partlabel/esp";
    fsType = "vfat";
  };

  systemd.services.qrtr-ns.enable = true;
  services.udev.extraRules = ''
    ENV{ID_INPUT_TOUCHSCREEN}=="1", ENV{LIBINPUT_CALIBRATION_MATRIX}="1 0 0 0 1 0 0 0 1"
  '';

  # 调用 NixOS 原生 Tarball 引擎进行纯净打包
  system.build.tarball = pkgs.callPackage "${pkgs.path}/nixos/lib/make-system-tarball.nix" {
    contents = [
      { source = "${config.system.build.toplevel}/."; target = "./"; }
    ];
    storeContents = [
      { object = config.system.build.toplevel; symlink = "none"; }
    ];
    extraCommands = "mkdir -p proc sys dev etc";
    extraArgs = "--owner=0";
  };
}
