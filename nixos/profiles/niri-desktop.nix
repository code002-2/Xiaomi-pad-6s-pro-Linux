# ---
# Module: Niri Desktop Profile
# Description: Niri scrollable-tiling Wayland compositor for sheng tablet
# Scope: System
# ---

{ config, lib, pkgs, vars, ... }:

{
  programs.niri.enable = true;
  hardware.graphics.enable = true;

  # kmscon conflicts with the compositor owning the display
  services.kmscon.enable = lib.mkForce false;

  # seatd manages DRM/input device access without a display manager
  services.seatd.enable = true;
  security.polkit.enable = true;

  # Auto-login on tty1 so bash loginShellInit can exec niri
  services.getty.autologinUser = lib.mkForce vars.username;

  users.users.${vars.username}.extraGroups = [ "video" "render" "input" ];

  environment.systemPackages = with pkgs; [
    niri
    foot
    fuzzel
  ];

  # Auto-start niri on the autologin tty (getty tty1)
  programs.bash.loginShellInit = ''
    if [ "$(tty)" = "/dev/tty1" ]; then
      exec niri-session
    fi
  '';
}
