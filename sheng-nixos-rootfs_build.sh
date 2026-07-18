#!/bin/bash
set -euo pipefail

# =============================================================================
# sheng-nixos-rootfs_build.sh — NixOS 25.05 rootfs builder for Xiaomi Pad 6S Pro
# =============================================================================
# Flow:
#   1. Create ext4 image
#   2. Install Nix on GitHub Actions runner (nix-community/setup-nix)
#   3. Build NixOS system closure via flakes + binary cache
#   4. Copy Nix store to image (nix copy)
#   5. Inject kernel .deb package
#   6. Generate initramfs
#   7. Hardware quirks (touchscreen, wifi, QRTR)
#   8. Pack sparse + 7z
# =============================================================================

source "$(dirname "$0")/lib/rootfs-common.sh"

# Resolve script directory to absolute path. When called via `sudo bash /abs/path/script.sh`,
# BASH_SOURCE[0] is the absolute path. When called with relative path, fall back to PWD.
if [ -n "${BASH_SOURCE[0]}" ] && [[ "${BASH_SOURCE[0]}" = /* ]]; then
    SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
else
    SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
fi

# Restore Nix PATH — sudo resets PATH, so we must re-add Nix bins explicitly.
# DeterminateSystems nix-installer places nix in two possible locations:
if [ -d /nix/var/nix/profiles/default/bin ]; then
    export PATH="/nix/var/nix/profiles/default/bin:$PATH"
fi
if [ -d /home/linuxbrew/.linuxbrew/bin ]; then
    export PATH="/home/linuxbrew/.linuxbrew/bin:$PATH"
fi

# Enable flakes via explicit CLI flag.
# Nix 2.34+ (Determinate Nix 3.21.5) no longer accepts --flake as a flag —
# flakes are enabled by default when the experimental feature is active.
# But we still pass --extra-experimental-features to ensure flakes are enabled.
FLAKES='--extra-experimental-features flakes --extra-experimental-features nix-command'

# --- Configuration ---
IMAGE_SIZE="8G"
UUID="ee8d3593-59b1-480e-a3b6-4fefb17ee7d8"
NIXOS_CONFIG_DIR="$SCRIPT_DIR/nixos"

# --- Password configuration (override via env vars) ---
ROOT_PASS="${ROOT_PASS:-1234}"
USER_PASS="${USER_PASS:-luser}"
USER_NAME="${USER_NAME:-luser}"

# --- Argument parsing ---
validate_args 2 4 $# '<distro-variant> <kernel_version> [boot_mode] [desktop_env]  (e.g. nixos 7.1 all niri)'
validate_root

DISTRO=$1
KERNEL=$2
TARGET_MODE="${3:-all}"
TARGET_DE="${4:-niri}"
TIMESTAMP=$(generate_timestamp)

mapfile -t BOOTMODES < <(parse_boot_modes "$TARGET_MODE") || exit 1

# --- Main build loop ---
for MODE in "${BOOTMODES[@]}"; do
    echo ""
    echo "======================================================"
    echo "Building: NixOS 25.05 | Desktop: niri | Mode: $MODE"
    echo "======================================================"

    ROOTFS_IMG="nixos_niri_${MODE}_${TIMESTAMP}.img"

    # Pre-flight checks
    preflight_checks 15360 nix rsync

    # Step 1: Create image
    create_image "$IMAGE_SIZE" "$ROOTFS_IMG" "$UUID"
    setup_chroot_mounts "$ROOTDIR"
    trap_teardown "$ROOTDIR"

    echo "Building NixOS system closure..."

    # Step 2: Build NixOS closure
    #   nix-community/setup-nix action installs Nix before this step in CI.
    #   For local builds, ensure Nix is installed first.
    export NIXPKGS_ALLOW_UNFREE=1

    # Pass GITHUB_TOKEN to nix for authenticated GitHub API access
    # during flake resolution.
    if [ -n "${GITHUB_TOKEN:-}" ]; then
        export NIX_GITHUB_OAUTH_TOKEN="$GITHUB_TOKEN" 2>/dev/null || true
        echo "   Using GitHub token for flake resolution" >&2
    fi

    # Copy NixOS flake closure to image store.
    # Strategy: use nix build to realise the NixOS system from binary cache,
    # then rsync the closure to the image.
    echo "Copying NixOS flake closure to image store..."
    mkdir -p "$ROOTDIR/nix/store"
    mkdir -p "$ROOTDIR/nix/var/nix/profiles"
    mkdir -p "$ROOTDIR/etc/nixos"

    echo "   Building NixOS system closure from binary cache..."
    # Use nix build with --no-link to download (not link) the toplevel derivation.
    # This should pull everything from cache.nixos.org / nix-community.cachix.org
    # without needing to build anything locally.
    #
    # We build nixosConfigurations.sheng.config.system.build.toplevel which
    # contains all user-space components. Kernel/initrd are injected separately
    # from .deb packages.
    #
    # Use directory#attribute syntax to force path-flake resolution.
    # Disable MNC substituter (prone to GitHub cache throttling) and use
    # cache.nixos.org directly as the primary substituter.
    BUILD_OUT=$(nix build "$NIXOS_CONFIG_DIR#nixosConfigurations.sheng.config.system.build.toplevel" \
        --print-out-paths --no-link \
        --option build-use-sandbox false \
        --option build-poll-interval 5 \
        --option substituters "https://cache.nixos.org https://nix-community.cachix.org" \
        --option trusted-public-keys "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY= nix-community.cachix.org-1:mB9FSh9qf2dNimDSK38dlRG8QZwyUKiBlbWPixHpmMo=" \
        --accept-flake-config \
        2>&1) || true
    echo "   DEBUG: build output='$BUILD_OUT'" >&2

    if [ -n "$BUILD_OUT" ]; then
        # Collect all store paths from build output (may be multi-line)
        echo "$BUILD_OUT" | while IFS= read -r sp; do
            if [ -e "$sp" ]; then
                echo "   Downloaded: $sp" >&2
                # Query the full closure of this path and rsync it
                CLOSURE=$(nix-store --query --requisites "$sp" 2>/dev/null) || true
                if [ -n "$CLOSURE" ]; then
                    echo "$CLOSURE" | while IFS= read -r req; do
                        if [ -e "$req" ]; then
                            rb=$(basename "$req")
                            rsync -aHAXx "$req/" "$ROOTDIR/nix/store/$rb/" 2>/dev/null || true
                        fi
                    done
                fi
            fi
        done
        echo "   Closure copied from nix build"
    else
        echo "   Warning: nix build failed, trying nix-prefetch-url fallback..." >&2
        # Fallback: prefetch nixpkgs tarball and copy its closure
        PREFETCH_OUT=$(nix-prefetch-url \
            --unpack \
            "https://github.com/NixOS/nixpkgs/archive/ac62194c3917d5f474c1a844b6fd6da2db95077d.tar.gz" \
            2>&1) || true

        # Extract store path (handles both Nix 2.34+ bare path and older formats)
        PREFETCH_PATH=$(echo "$PREFETCH_OUT" | grep -oE '/nix/store/[a-z0-9]{32}-.*' | head -1) || true
        echo "   DEBUG: prefetch_out='$PREFETCH_OUT'" >&2
        echo "   DEBUG: prefetch_path='$PREFETCH_PATH'" >&2

        if [ -n "$PREFETCH_PATH" ] && [ -d "$PREFETCH_PATH" ]; then
            echo "   Prefetched nixpkgs to: $PREFETCH_PATH"
            CLOSURE=$(nix-store --query --requisites "$PREFETCH_PATH" 2>/dev/null) || true
            if [ -n "$CLOSURE" ]; then
                echo "$CLOSURE" | while IFS= read -r sp; do
                    if [ -e "$sp" ]; then
                        sb=$(basename "$sp")
                        rsync -aHAXx "$sp/" "$ROOTDIR/nix/store/$sb/" 2>/dev/null || true
                    fi
                done
                echo "   Closure copied from prefetch fallback"
            fi
        fi
    fi
    echo "   NixOS closure copy complete"

    # nix copy --to file:// already transferred the entire closure
    # to the image's /nix/store, including profiles and configs.
    # No need to manually copy RESULT contents.

    # Step 4: Setup DNS (NixOS uses systemd-resolved)
    setup_systemd_resolved_symlink "$ROOTDIR"

    # Step 5: Inject kernel .deb
    echo "Injecting kernel .deb package..."
    if ! inject_deb_kernel "$ROOTDIR"; then
        echo "Error: No .deb kernel packages found, cannot create bootable rootfs!" >&2
        exit 1
    fi

    KERNEL_MODULE_DIR=$(detect_kernel_module_dir "$ROOTDIR")
    if [ -n "$KERNEL_MODULE_DIR" ]; then
        echo "   Detected kernel module dir: $KERNEL_MODULE_DIR"
        chroot "$ROOTDIR" depmod -a "$KERNEL_MODULE_DIR" 2>/dev/null || true
    fi

    # Step 6: Generate initramfs from injected kernel
    echo "Generating initramfs..."
    mkdir -p "$ROOTDIR/boot"

    if [ -n "$KERNEL_MODULE_DIR" ]; then
        echo "   Generating initramfs for kernel $KERNEL_MODULE_DIR..."
        # Try multiple initrd generation methods in order of preference:
        # 1. nixos-generate-initrd (NixOS-specific, knows about the system closure)
        # 2. dracut (generic, widely available in NixOS)
        # 3. mkinitcpio (Arch-style, unlikely but possible)
        # 4. Fallback: find initrd in NixOS store

        INITRD_GENERATED=0

        # Method 1: nixos-generate-initrd
        if [ -f "$ROOTDIR/usr/bin/nixos-generate-initrd" ] && [ "$INITRD_GENERATED" -eq 0 ]; then
            echo "   Using nixos-generate-initrd..."
            chroot "$ROOTDIR" nixos-generate-initrd \
                --system /nix/var/nix/profiles/system \
                --output /boot/initrd.img 2>/dev/null && INITRD_GENERATED=1 || true
        fi

        # Method 2: dracut
        if [ -f "$ROOTDIR/usr/bin/dracut" ] && [ "$INITRD_GENERATED" -eq 0 ]; then
            echo "   Using dracut..."
            chroot "$ROOTDIR" dracut --kver "$KERNEL_MODULE_DIR" --force /boot/initrd.img "$KERNEL_MODULE_DIR" 2>/dev/null && INITRD_GENERATED=1 || true
        fi

        # Method 3: mkinitcpio
        if [ -f "$ROOTDIR/bin/mkinitcpio" ] && [ "$INITRD_GENERATED" -eq 0 ]; then
            echo "   Using mkinitcpio..."
            chroot "$ROOTDIR" mkinitcpio -G /boot/initrd.img 2>/dev/null && INITRD_GENERATED=1 || true
        fi

        # Method 4: Find pre-built initrd in NixOS store
        if [ "$INITRD_GENERATED" -eq 0 ]; then
            INITRD_CANDIDATE=$(find "$ROOTDIR/nix/store" -path "*/nixos-system-*/initrd/nixos/initrd" -type f 2>/dev/null | head -1)
            if [ -n "$INITRD_CANDIDATE" ]; then
                cp "$INITRD_CANDIDATE" "$ROOTDIR/boot/initrd.img"
                echo "   Copied initrd from NixOS store"
                INITRD_GENERATED=1
            fi
        fi

        if [ "$INITRD_GENERATED" -eq 0 ]; then
            echo "   Warning: Could not generate initrd, tablet may not boot" >&2
        fi
    fi

    # Copy vmlinuz -> Image (the kernel from the injected .deb)
    if [ -n "$KERNEL_MODULE_DIR" ]; then
        if [ -f "$ROOTDIR/boot/vmlinuz-$KERNEL_MODULE_DIR" ]; then
            cp "$ROOTDIR/boot/vmlinuz-$KERNEL_MODULE_DIR" "$ROOTDIR/boot/Image"
            echo "   vmlinuz -> Image copy complete"
        fi
    fi

    # Step 7: Hardware quirks
    echo "Configuring hardware patches..."

    # Install custom services (devauth binary)
    if [ -f "../sheng-devauth" ]; then
        cp "../sheng-devauth" "$ROOTDIR/usr/local/bin/sheng-devauth"
        chmod 755 "$ROOTDIR/usr/local/bin/sheng-devauth"
        echo "   devauth binary installed"
    elif [ -f "sheng-devauth" ]; then
        cp "sheng-devauth" "$ROOTDIR/usr/local/bin/sheng-devauth"
        chmod 755 "$ROOTDIR/usr/local/bin/sheng-devauth"
        echo "   devauth binary installed"
    fi

    setup_getty_ttyMSM0 "$ROOTDIR"
    configure_touchscreen "$ROOTDIR"
    fix_wifi_firmware "$ROOTDIR"
    setup_qrtr_service "$ROOTDIR"

    # Enable NetworkManager
    chroot "$ROOTDIR" systemctl enable NetworkManager

    # Step 8: fstab
    generate_fstab "$ROOTDIR" "$MODE"

    # Step 9: Cleanup
    echo "Cleaning up..."
    # NOTE: Do NOT run nix-collect-garbage on the rootfs — it would delete
    # the Nix store we just copied. The NixOS closure is already minimal.
    teardown_mounts "$ROOTDIR"

    # Step 10: Pack
    apply_fs_uuid "$UUID" "$ROOTFS_IMG"

    echo "Converting to sparse image and compressing..."
    pack_sparse_image "$ROOTFS_IMG" "${ROOTFS_IMG%.img}.7z"

    echo "[niri - $MODE] Build complete! Artifact: ${ROOTFS_IMG%.img}.7z"
done

echo "[OK] NixOS image packaging complete!"
