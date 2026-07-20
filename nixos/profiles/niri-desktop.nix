# ---
# Module: Niri Desktop Profile
# Description: Niri scrollable-tiling Wayland compositor for sheng tablet
# Scope: System
# ---

{ config, lib, pkgs, vars, ... }:

let
  nyxNiriWallpapers = pkgs.fetchzip {
    name = "nyx-niri-wallpapers";
    url = "https://github.com/ech678/NyxNiri/archive/79894f443f5b21bb16077f628a35d9c47301b15d.tar.gz";
    hash = "sha256-Jj5cKMJJCIZlC2gUKTWe9CHZCm7HpcWlJ5OCfQxw4+k=";
    stripRoot = false;
  };

  wallpaperStorePath = "${nyxNiriWallpapers}/NyxNiri-79894f443f5b21bb16077f628a35d9c47301b15d/Wallpapers";

  wallpaperSwitch = pkgs.writeShellScriptBin "wallpaper-switch" ''
    set -euo pipefail

    WALLPAPER_DIR="/var/lib/wallpapers"
    STATE_FILE="$HOME/.cache/wallpaper-state"
    ACTION="''${1:-next}"

    mkdir -p "$HOME/.cache"

    mapfile -t walls < <(find "$WALLPAPER_DIR" -type f \
      \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" \
         -o -iname "*.mp4" -o -iname "*.webm" -o -iname "*.mkv" \) | sort)
    TOTAL=''${#walls[@]}

    if [ "$TOTAL" -eq 0 ]; then
      echo "No wallpapers found in $WALLPAPER_DIR — run wallpaper-sync first" >&2
      exit 1
    fi

    if [ -f "$STATE_FILE" ]; then
      CURRENT_INDEX=$(cat "$STATE_FILE")
    else
      CURRENT_INDEX=0
    fi

    case "$ACTION" in
      next)
        CURRENT_INDEX=$(( (CURRENT_INDEX + 1) % TOTAL ))
        ;;
      prev)
        CURRENT_INDEX=$(( (CURRENT_INDEX - 1 + TOTAL) % TOTAL ))
        ;;
      pick)
        noctalia msg panel-toggle wallpaper
        exit 0
        ;;
      *)
        echo "Usage: wallpaper-switch {next|prev|pick}"
        exit 1
        ;;
    esac

    echo "$CURRENT_INDEX" > "$STATE_FILE"
    WALLPAPER="''${walls[$CURRENT_INDEX]}"

    # Stop any running wallpaper process
    pkill swaybg 2>/dev/null || true
    pkill mpvpaper 2>/dev/null || true
    sleep 0.1

    EXT="''${WALLPAPER##*.}"
    case "''${EXT,,}" in
      mp4|webm|mkv)
        mpvpaper -o "no-audio loop" '*' "$WALLPAPER" &
        ;;
      *)
        swaybg -i "$WALLPAPER" -m fill &
        ;;
    esac
    echo "Wallpaper: $(basename "$WALLPAPER")"
  '';

  wallpaperLaunch = pkgs.writeShellScriptBin "wallpaper-launch" ''
    set -euo pipefail
    WALLPAPER_DIR="/var/lib/wallpapers"
    STATE_FILE="$HOME/.cache/wallpaper-state"

    mkdir -p "$HOME/.cache"

    if [ -f "$STATE_FILE" ]; then
      INDEX=$(cat "$STATE_FILE")
    else
      INDEX=0
      echo 0 > "$STATE_FILE"
    fi

    mapfile -t walls < <(find "$WALLPAPER_DIR" -type f \
      \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" \
         -o -iname "*.mp4" -o -iname "*.webm" -o -iname "*.mkv" \) | sort)
    if [ "''${#walls[@]}" -gt 0 ]; then
      WALL="''${walls[$(( INDEX % ''${#walls[@]} ))]}"
      EXT="''${WALL##*.}"
      case "''${EXT,,}" in
        mp4|webm|mkv)
          mpvpaper -o "no-audio loop" '*' "$WALL" &
          ;;
        *)
          swaybg -i "$WALL" -m fill &
          ;;
      esac
    fi
  '';

  noctaliaPkg = pkgs.stdenv.mkDerivation {
    pname = "noctalia";
    version = "5.0.0-beta.3";

    src = pkgs.fetchzip {
      name = "noctalia-source";
      url = "https://github.com/noctalia-dev/noctalia/archive/v5.0.0-beta.3.tar.gz";
      hash = "sha256-8iAeWIjw2OMfsBCtaGcmR14lgBX0MOoaBaSyBwieBsA=";
    };

    postPatch = ''
      sed -i "s/'-march=native', '-mtune=native',//" meson.build
      # Fix sdbus-cpp API change: PollData.eventFd renamed
      substituteInPlace src/dbus/system_bus_poll_source.h \
        --replace-fail "pd.eventFd" "pd.fd"
    '';

    postFixup = ''
      wrapProgram $out/bin/noctalia \
        --prefix PATH : ${pkgs.lib.makeBinPath [ pkgs.git ]}
    '';

    nativeBuildInputs = with pkgs; [
      meson
      ninja
      pkg-config
      wayland-scanner
      jemalloc
      makeWrapper
    ];

    buildInputs = with pkgs; [
      wayland
      wayland-protocols
      libGL
      libglvnd
      freetype
      fontconfig
      cairo
      pango
      harfbuzz
      libxkbcommon
      sdbus-cpp_2
      systemd
      pipewire
      pam
      curl
      libwebp
      glib
      polkit
      librsvg
      libqalculate
      libxml2
      md4c
      (stb.overrideAttrs (_: {
        version = "unstable-2025-10-26";
        src = pkgs.fetchzip {
          name = "stb-source";
          url = "https://github.com/nothings/stb/archive/f1c79c02822848a9bed4315b12c8c8f3761e1296.tar.gz";
          hash = "sha256-BlyXJtAI7WqXCTT3ylww8zoG0hBxaojJnQDvdQOXJPE=";
        };
      }))
      nlohmann_json
      tomlplusplus
      wireplumber
    ];

    mesonBuildType = "release";
    ninjaFlags = [ "-v" ];

    meta = with pkgs.lib; {
      description = "A desktop shell for Wayland compositors";
      homepage = "https://github.com/noctalia-dev/noctalia";
      license = licenses.mit;
      platforms = platforms.linux;
      mainProgram = "noctalia";
    };
  };
in

{
  programs.niri.enable = true;
  hardware.graphics = {
    enable = true;
    # Qualcomm Adreno 740 — ensure freedreno (GL) + turnip (VK) are included
    extraPackages = with pkgs; [
      mesa.drivers
    ];
  };

  # kmscon conflicts with the compositor owning the display
  services.kmscon.enable = lib.mkForce false;

  # logind manages DRM/input device access (compatible with niri --session)
  security.polkit.enable = true;

  # Allow user session to manage DRM and input devices via logind
  services.logind.extraConfig = ''
    HandlePowerKey=ignore
    IdleAction=ignore
  '';
  users.users.${vars.username}.extraGroups = [ "video" "input" "render" ];

  # Auto-login on tty1 so bash loginShellInit can exec niri
  services.getty.autologinUser = lib.mkForce vars.username;

  environment.systemPackages = with pkgs; [
    niri
    foot
    kitty
    wvkbd
    wallpaperSwitch
    wallpaperLaunch
    swaybg
    procps
    gnused
    mpvpaper
    fastfetch
    eza
    fzf
    fd
    bat
    jq
    inotify-tools
    glmark2
    vkmark
    vulkan-tools
    mesa-demos
    noctaliaPkg
  ];

  fonts.packages = with pkgs; [
    jetbrains-mono
    nerd-fonts.jetbrains-mono
    noto-fonts-cjk-sans
  ];

  programs.fish.enable = true;
  programs.starship = {
    enable = true;
    settings = {
      format = "$all";
      character = {
        success_symbol = "[λ](bold green)";
        error_symbol = "[λ](bold red)";
      };
      directory = {
        truncation_length = 3;
        truncate_to_repo = false;
      };
      git_branch = {
        format = "[$symbol$branch]($style) ";
        symbol = "";
        style = "bold purple";
      };
      git_status = {
        format = "([$all_status$ahead_behind]($style)) ";
        style = "bold yellow";
      };
      cmd_duration = {
        format = "[$duration]($style) ";
        min_time = 2000;
        style = "bold yellow";
      };
    };
  };

  # Auto-start niri on the autologin tty (getty tty1)
  programs.bash.loginShellInit = ''
    if [ "$(tty)" = "/dev/tty1" ]; then
      echo "Starting niri compositor..." >&2

      # Dump input device info for diagnostics
      mkdir -p /tmp/niri-diag
      echo "=== $(date) ===" > /tmp/niri-diag/devices.log
      echo "--- input events ---" >> /tmp/niri-diag/devices.log
      ls -la /dev/input/event* >> /tmp/niri-diag/devices.log 2>&1
      echo "--- by-path ---" >> /tmp/niri-diag/devices.log
      ls -la /dev/input/by-path/ >> /tmp/niri-diag/devices.log 2>&1
      echo "--- by-id ---" >> /tmp/niri-diag/devices.log
      ls -la /dev/input/by-id/ >> /tmp/niri-diag/devices.log 2>&1
      echo "--- libinput ---" >> /tmp/niri-diag/devices.log
      libinput list-devices >> /tmp/niri-diag/devices.log 2>&1
      echo "--- usb devices ---" >> /tmp/niri-diag/devices.log
      lsusb >> /tmp/niri-diag/devices.log 2>&1
      echo "--- kernel modules (hid/usb) ---" >> /tmp/niri-diag/devices.log
      lsmod | grep -iE "hid|usb" >> /tmp/niri-diag/devices.log 2>&1

      # Wait for DRM devices to appear (can take a moment after boot)
      DRM_READY=false
      for i in $(seq 1 30); do
        if ls /dev/dri/card* >/dev/null 2>&1; then
          DRM_READY=true
          break
        fi
        echo "Waiting for /dev/dri/card* (attempt $i/30)..." >> /tmp/niri-diag/devices.log
        sleep 1
      done

      if ! $DRM_READY; then
        echo "ERROR: No DRM device found at /dev/dri/ after 10 attempts" >&2
        echo "ERROR: No DRM device after 10 attempts" >> /tmp/niri-diag/devices.log
      fi

      # Wait for seatd
      SEATD_READY=false
      for i in $(seq 1 10); do
        if systemctl is-active --quiet seatd 2>/dev/null; then
          SEATD_READY=true
          break
        fi
        echo "Waiting for seatd (attempt $i/10)..." >> /tmp/niri-diag/devices.log
        sleep 0.5
      done

      if ! $SEATD_READY; then
        echo "ERROR: seatd is not running after 10 attempts" >&2
        echo "ERROR: seatd not running after 10 attempts" >> /tmp/niri-diag/devices.log
        echo "  systemctl status: $(systemctl is-active seatd 2>&1 || true)" >> /tmp/niri-diag/devices.log
      fi

      if $DRM_READY && $SEATD_READY; then
        exec niri --session 2>> /tmp/niri-diag/niri-stderr.log
      else
        echo "Falling back to shell. Run 'niri --session' to start manually." >&2
      fi
    fi
  '';

  environment.etc."xdg/niri/config.kdl".text = ''
    // ==========================================
    // NyxNiri V2 niri config — adapted for tablet
    // ==========================================

    spawn-at-startup "kitty"
    spawn-at-startup "wvkbd-mobintl"
    spawn-at-startup "wallpaper-launch"
    spawn-at-startup "noctalia"

    prefer-no-csd
    screenshot-path "~/Pictures/Screenshots/Screenshot from %Y-%m-%d %H-%M-%S.png"

    // --- Input ---
    input {
        keyboard {
            xkb-layout "us"
        }
        touch {
            tap true
        }
        touchpad {
            tap true
            natural-scroll true
        }
    }

    // --- Layout & Visual Effects ---
    blur {
        passes 3
        offset 2.3
        noise 0.001
        saturation 2
    }

    layout {
        background-color "transparent"
        gaps 12
        center-focused-column "never"
        preset-column-widths {
            proportion 0.33333
            proportion 0.5
            proportion 0.66667
        }
        default-column-width { proportion 0.5; }
        focus-ring { off; width 0; }
        shadow { on; softness 10; spread 4; offset x=0 y=0; color "#00000070"; }
        tab-indicator { active-color "#60cdff"; inactive-color "#3b3b3b"; }
        insert-hint { color "#0078d480"; }
    }

    // --- Global Window Rules ---
    window-rule {
        geometry-corner-radius 12
        clip-to-geometry true
        draw-border-with-background false
        opacity 0.95
        background-effect { blur true; }
    }

    window-rule {
        match is-focused=false
        opacity 0.88
    }

    // --- Layer Rules ---
    layer-rule {
        match namespace="^mpvpaper$"
        place-within-backdrop true
    }

    layer-rule {
        match namespace="^noctalia-bar-"
        opacity 1.0
        geometry-corner-radius 0
        shadow { off; }
        background-effect { blur false; }
    }

    layer-rule {
        match namespace="^noctalia-wallpaper-"
        place-within-backdrop true
    }

    // --- Overview ---
    overview {
        backdrop-color "#20202090"
    }

    // --- Environment ---
    environment {
        XDG_CURRENT_DESKTOP "niri"
        XDG_SESSION_TYPE "wayland"
        ELECTRON_OZONE_PLATFORM_HINT "auto"
        QT_QPA_PLATFORM "wayland"
        QT_QPA_PLATFORMTHEME "gtk3"
        QT_WAYLAND_DISABLE_WINDOWDECORATION "1"
    }

    // --- Cursor ---
    cursor {
        xcursor-theme "Adwaita"
        xcursor-size 24
    }

    // --- Animations ---
    animations {
        workspace-switch { spring damping-ratio=0.8 stiffness=523 epsilon=0.0001; }
        window-open { duration-ms 150; curve "ease-out-expo"; }
        window-close { duration-ms 150; curve "ease-out-quad"; }
        horizontal-view-movement { spring damping-ratio=0.85 stiffness=423 epsilon=0.0001; }
        window-movement { spring damping-ratio=0.75 stiffness=323 epsilon=0.0001; }
        window-resize { spring damping-ratio=0.85 stiffness=423 epsilon=0.0001; }
        config-notification-open-close { spring damping-ratio=0.65 stiffness=923 epsilon=0.001; }
        screenshot-ui-open { duration-ms 200; curve "ease-out-quad"; }
        overview-open-close { spring damping-ratio=0.85 stiffness=800 epsilon=0.0001; }
    }

    // --- Alt+Tab Switcher ---
    recent-windows {
        binds {
            Alt+Tab         { next-window scope="output"; }
            Alt+Shift+Tab   { previous-window scope="output"; }
        }
        highlight {
            corner-radius 12
            active-color "#b6c7e7"
        }
    }

    // --- Floating Windows ---
    window-rule {
        match app-id=r"^org\.gnome\.Nautilus$"
        match app-id=r"^org\.gnome\.Calculator$"
        match app-id=r"^gnome-calculator$"
        match app-id=r"^blueman-manager$"
        match app-id=r"^xdg-desktop-portal$"
        open-floating true
    }

    window-rule {
        match app-id=r"^gnome-control-center$"
        match app-id=r"^pavucontrol$"
        match app-id=r"^nm-connection-editor$"
        default-column-width { proportion 0.5; }
        open-floating false
    }

    // Picture-in-Picture
    window-rule {
        match title="画中画"
        match title="Picture-in-Picture"
        open-floating true
        opacity 1.0
        default-column-width
        default-window-height
        default-floating-position x=20 y=20 relative-to="bottom-right"
    }

    hotkey-overlay { skip-at-startup }

    // ==========================================
    // Keybindings
    // ==========================================
    binds {
        Mod+Tab repeat=false { toggle-overview; }
        Mod+Return           { spawn "kitty"; }
        Mod+T                { spawn "kitty"; }
        Mod+Q                { close-window; }
        Mod+Shift+E          { quit; }
        Mod+Shift+R          { spawn "niri" "msg" "action" "load-config-file"; }

        // Launcher via noctalia
        Mod+D                { spawn "noctalia" "msg" "launcher" "toggle"; }

        // Movement
        Mod+H                { focus-column-left; }
        Mod+L                { focus-column-right; }
        Mod+J                { focus-window-down; }
        Mod+K                { focus-window-up; }
        Mod+Shift+H          { move-column-left; }
        Mod+Shift+L          { move-column-right; }
        Mod+Shift+J          { move-window-down; }
        Mod+Shift+K          { move-window-up; }

        Mod+F                { maximize-column; }
        Mod+Shift+F          { fullscreen-window; }
        Mod+Space            { switch-preset-column-width; }
        Mod+Comma            { consume-window-into-column; }
        Mod+Period           { expel-window-from-column; }

        // Workspaces
        Mod+1                { focus-workspace 1; }
        Mod+2                { focus-workspace 2; }
        Mod+3                { focus-workspace 3; }
        Mod+4                { focus-workspace 4; }
        Mod+5                { focus-workspace 5; }
        Mod+Shift+1          { move-column-to-workspace 1; }
        Mod+Shift+2          { move-column-to-workspace 2; }
        Mod+Shift+3          { move-column-to-workspace 3; }

        // Scroll navigation
        Mod+WheelScrollDown  cooldown-ms=150 { focus-workspace-down; }
        Mod+WheelScrollUp    cooldown-ms=150 { focus-workspace-up; }

        // Screenshot & overlay
        Mod+S                { screenshot; }
        Mod+Slash            { show-hotkey-overlay; }

        // Wallpaper switcher
        Mod+Ctrl+N           { spawn "wallpaper-switch" "next"; }
        Mod+Ctrl+P           { spawn "wallpaper-switch" "prev"; }
        Mod+Ctrl+W           { spawn "wallpaper-switch" "pick"; }

        // Audio
        XF86AudioRaiseVolume { spawn "wpctl" "set-volume" "@DEFAULT_AUDIO_SINK@" "5%+"; }
        XF86AudioLowerVolume { spawn "wpctl" "set-volume" "@DEFAULT_AUDIO_SINK@" "5%-"; }
        XF86AudioMute        { spawn "wpctl" "set-mute" "@DEFAULT_AUDIO_SINK@" "toggle"; }
    }
  '';

  system.activationScripts.niriSetup = ''
    mkdir -p /home/${vars.username}/.config/niri /home/${vars.username}/.config/noctalia
    ln -sf /etc/xdg/niri/config.kdl /home/${vars.username}/.config/niri/config.kdl
    chown ${vars.username}:users /home/${vars.username}/.config
    chown -R ${vars.username}:users /home/${vars.username}/.config/niri /home/${vars.username}/.config/noctalia
  '';

  # Symlink noctalia config into user home on activation
  system.activationScripts.noctaliaConfig = ''
    mkdir -p /home/${vars.username}/.config/noctalia
    ln -sf /etc/xdg/noctalia/config.toml /home/${vars.username}/.config/noctalia/config.toml
    chown -R ${vars.username}:users /home/${vars.username}/.config/noctalia
  '';

  # Copy wallpapers from read-only Nix store to writable /var/lib on boot
  systemd.services.wallpaper-sync = {
    wantedBy = [ "multi-user.target" ];
    before = [ "getty@tty1.service" "getty@tty2.service" "getty@tty3.service" ];
    script = ''
      mkdir -p /var/lib/wallpapers
      cp -r ${wallpaperStorePath}/* /var/lib/wallpapers/
      chown -R ${vars.username}:users /var/lib/wallpapers
    '';
    serviceConfig.Type = "oneshot";
    serviceConfig.RemainAfterExit = true;
  };

  environment.etc."xdg/noctalia/config.toml".text = ''
    # Noctalia V5 — tablet config for sheng

    [shell]
    corner_radius_scale     = 1.0
    font_family             = "JetBrains Mono"
    time_format             = "{:%H:%M}"
    offline_mode            = false
    telemetry_enabled       = false
    clipboard_enabled       = true
    clipboard_history_max_entries = 100
    clipboard_auto_paste    = "auto"

    [shell.animation]
    enabled = true
    speed   = 1.0

    [shell.shadow]
    direction = "down"
    alpha     = 0.55

    [shell.panel]
    transparency_mode  = "glass"
    borders            = true
    shadow             = true
    launcher_placement = "centered"

    [shell.launcher]
    categories      = true
    show_icons      = true
    sort_by_usage   = true

    [theme]
    mode   = "dark"
    source = "builtin"
    builtin = "Catppuccin"

    [wallpaper]
    enabled       = true
    fill_mode     = "crop"
    transition    = ["fade"]
    transition_duration = 800
    directory     = "/var/lib/wallpapers"

    [notification]
    enable_daemon      = true
    show_app_name      = true
    show_actions       = true
    layer              = "top"
    offset_x           = 20
    offset_y           = 8

    [osd]
    position = "top_center"
    offset_x = 20
    offset_y = 8

    [lockscreen]
    enabled         = true
    blurred_desktop = true

    [bar.main]
    position           = "top"
    thickness          = 38
    background_opacity = 0.79
    radius             = 14
    margin_h           = 10
    margin_v           = 6
    padding            = 12
    widget_spacing     = 4
    scale              = 1.0
    shadow             = true
    auto_hide          = false
    reserve_space      = true
    capsule            = true
    capsule_radius     = 14.0

    start  = ["launcher", "workspaces"]
    center = ["clock"]
    end    = ["media", "tray", "network", "volume", "battery", "wallpaper", "session"]

    [widget.clock]
    format = "{:%H:%M}"
    tooltip_format = "{:%A, %B %d, %Y}"
    scale = 1.0
    font_weight = 600

    [idle.behavior.lock]
    timeout = 600
    action = "lock"
    enabled = false

    [idle.behavior.screen-off]
    timeout = 660
    action = "screen_off"
    enabled = false
  '';

  programs.bash.interactiveShellInit = ''
    if command -v fish > /dev/null 2>&1; then
      exec fish
    fi
  '';

  environment.etc."xdg/kitty/kitty.conf".text = ''
    # Catppuccin Mocha theme for Kitty
    font_family JetBrainsMono Nerd Font Mono
    font_size 12.0
    bold_font auto
    italic_font auto
    bold_italic_font auto
    cursor_trail 3
    cursor_trail_start_threshold 1
    cursor_trail_decay 0.1
    disable_ligatures never
    background_opacity 0.95
    dynamic_background_opacity yes
    confirm_os_window_close 0
    hide_window_decorations yes
    window_padding_width 8

    # Catppuccin Mocha colors
    foreground #cdd6f4
    background #1e1e2e
    selection_foreground #1e1e2e
    selection_background #f5e0dc
    url_color #f5c2e7
    cursor #f5e0dc
    active_border_color #b4befe
    inactive_border_color #6c7086
    active_tab_foreground #11111b
    active_tab_background #cba6f7
    inactive_tab_foreground #cdd6f4
    inactive_tab_background #181825
    tab_bar_background #11111b
    color0 #45475a
    color1 #f38ba8
    color2 #a6e3a1
    color3 #f9e2af
    color4 #89b4fa
    color5 #f5c2e7
    color6 #94e2d5
    color7 #bac2de
    color8 #585b70
    color9 #f38ba8
    color10 #a6e3a1
    color11 #f9e2af
    color12 #89b4fa
    color13 #f5c2e7
    color14 #94e2d5
    color15 #a6adc8

    # NyxNiri-style keybindings
    map ctrl+c copy_or_interrupt
    map ctrl+v paste_from_clipboard
    map ctrl+backspace send_text all \x17
    map ctrl+delete send_text all \x1b\x64
    map ctrl+a send_text all \x01
  '';

  environment.etc."xdg/fastfetch/config.jsonc".text = ''
    {
      "$schema": "https://github.com/fastfetch-cli/fastfetch/raw/dev/doc/json_schema.json",
      "modules": [
        "title",
        "separator",
        "os",
        "host",
        "kernel",
        "uptime",
        "packages",
        "shell",
        "display",
        "wm",
        "terminal",
        "cpu",
        "gpu",
        "memory",
        "break",
        "colors"
      ],
      "display": {
        "separator": " → "
      },
      "logo": { "type": "small" }
    }
  '';
}
