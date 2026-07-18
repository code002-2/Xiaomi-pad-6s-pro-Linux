# ---
# Module: User Profile
# Description: Home Manager configuration for the dynamic user
# Scope: Home Manager
# ---

{ pkgs, lib, vars, ... }:

{
  home.username = vars.username;
  home.homeDirectory = "/home/${vars.username}";
  home.stateVersion = "25.05";

  # Workaround for Home Manager unstable zipAttrsWith conflict on fontconfig
  fonts.fontconfig.enable = lib.mkForce false;

  programs.home-manager.enable = true;

  programs.bash = {
    enable = true;
    shellAliases = {
      nixsrc = "cd /home/${vars.username}/nixos-sheng/nixos";
      nrs = "sudo nixos-rebuild switch --flake /home/${vars.username}/nixos-sheng/nixos#sheng";
      hms = "home-manager switch --flake /home/${vars.username}/nixos-sheng/nixos#${vars.username}@sheng";
    };
  };

  home.packages = with pkgs; [
    curl
    evtest
    gitMinimal
    brightnessctl
    iproute2
    iw
    nano
    pciutils
    usbutils
    vim
    wget
  ];
}
