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

  environment.systemPackages = with pkgs; [
    niri
    foot
    fuzzel
  ];

  # Auto-start niri on the autologin tty (getty tty1)
  programs.bash.loginShellInit = ''
    if [ "$(tty)" = "/dev/tty1" ]; then
      echo "Starting niri compositor..." >&2
      if ! ls /dev/dri/card* >/dev/null 2>&1; then
        echo "ERROR: No DRM device found at /dev/dri/" >&2
      elif ! systemctl is-active --quiet seatd 2>/dev/null; then
        echo "ERROR: seatd is not running" >&2
        echo "  status: $(systemctl is-active seatd 2>&1)" >&2
      else
        exec niri-session
      fi
    fi
  '';
}
