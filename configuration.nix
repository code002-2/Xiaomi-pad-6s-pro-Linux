{ config, pkgs, ... }:

{
  # 引导加载器：NixOS 默认使用 systemd-boot (要求你有一个 FAT32 的 esp 分区)
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = "arch-sheng"; # 虽然叫 arch，但我们是 NixOS 啦
  networking.networkmanager.enable = true;

  # 本地化设置
  time.timeZone = "Asia/Shanghai";
  i18n.defaultLocale = "en_US.UTF-8";

  # 桌面环境 (GNOME) 与 GDM 自动登录
  services.xserver.enable = true;
  services.xserver.displayManager.gdm.enable = true;
  services.xserver.desktopManager.gnome.enable = true;
  services.displayManager.autoLogin.enable = true;
  services.displayManager.autoLogin.user = "luser";

  # 声明普通用户 (等同于 useradd 和 usermod)
  users.users.luser = {
    isNormalUser = true;
    description = "Sheng User";
    extraGroups = [ "networkmanager" "wheel" "audio" "video" "input" ];
    initialPassword = "luser"; # 初始密码
  };

  # 声明 Root 密码
  users.users.root.initialPassword = "1234";

  # 允许 wheel 组免密 sudo (等同于你修改 sudoers)
  security.sudo.wheelNeedsPassword = false;

  # 安装基础软件
  environment.systemPackages = with pkgs; [
    vim wget curl dialog pciutils usbutils
  ];

  # NixOS 版本号 (不要修改)
  system.stateVersion = "24.05";
}
