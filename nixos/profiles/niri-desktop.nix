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
    wvkbd
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

  environment.etc."xdg/niri/config.kdl".text = ''
    // Auto-start terminal and on-screen keyboard
    spawn-at-startup "foot"
    spawn-at-startup "wvkbd-mobintl"

    // Input: use libinput defaults, tap-to-click for touchscreen
    input {
        touch {
            tap
        }
        touchpad {
            tap
        }
        keyboard {
            xkb-layout "us"
        }
    }

    // Keyboard shortcuts (Mod = Super/Win key)
    binds {
        Mod+Return { spawn "foot"; }
        Mod+T { spawn "foot"; }
        Mod+D { spawn "fuzzel"; }
        Mod+Q { close-window; }
        Mod+H { focus-column-left; }
        Mod+L { focus-column-right; }
        Mod+J { focus-window-down; }
        Mod+K { focus-window-up; }
        Mod+1 { switch-to-workspace 1; }
        Mod+2 { switch-to-workspace 2; }
        Mod+3 { switch-to-workspace 3; }
    }
  '';
}
