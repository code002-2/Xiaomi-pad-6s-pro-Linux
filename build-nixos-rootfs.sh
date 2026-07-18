#!/usr/bin/env bash
set -euo pipefail

# =============================================================================
# NixOS RootFS & Boot Image Builder for Xiaomi Pad 6S Pro (sheng)
# =============================================================================
#
# Phase 1: 通过 Mobile NixOS flake 构建 rootfs
# Phase 2: 编译 boot 内核镜像 (Mobile NixOS + mkbootimg 双保险)
#
# 环境变量:
#   BOOT_MODE          启动模式: dual | single | all
#   IMAGE_SIZE         镜像大小: 8G | auto
#   ROOTFS_FLAKE_ATTR  Nix flake 属性: mobileRootfsImage
#   FILESYSTEM_UUID    文件系统 UUID
#   ROOT_PASS / USER_PASS / USER_NAME  凭据
#   NIX_BUILD_FLAGS    (可选) 额外 nix build 标志
# =============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/rootfs-common.sh"

# --- 配置 ---
BOOT_MODE="${BOOT_MODE:-all}"
IMAGE_SIZE="${IMAGE_SIZE:-8G}"
ROOTFS_FLAKE_ATTR="${ROOTFS_FLAKE_ATTR:-mobileRootfsImage}"
FILESYSTEM_UUID="${FILESYSTEM_UUID:-ee8d3593-59b1-480e-a3b6-4fefb17ee7d8}"
TIMESTAMP="$(generate_timestamp)"
OUT_DIR="${OUT_DIR:-out}"

ROOT_PASS="${ROOT_PASS:-1234}"
USER_PASS="${USER_PASS:-luser}"
USER_NAME="${USER_NAME:-luser}"

NIXOS_CONFIG_DIR="$SCRIPT_DIR/nixos"

if [ -n "${NIX_BUILD_FLAGS:-}" ]; then
    read -r -a NIX_BUILD_FLAGS_ARRAY <<< "${NIX_BUILD_FLAGS}"
else
    NIX_BUILD_FLAGS_ARRAY=(--fallback)
fi

export NIXPKGS_ALLOW_UNFREE=1

# --- 工具检查 ---
if ! command -v nix >/dev/null 2>&1; then
    echo "Error: nix is required. Install Nix with flakes enabled first." >&2
    exit 1
fi
if ! command -v tune2fs >/dev/null 2>&1 || ! command -v e2fsck >/dev/null 2>&1; then
    echo "Error: e2fsprogs is required (tune2fs, e2fsck). Install it first." >&2
    exit 1
fi

# --- 注入动态凭据到 vars.nix ---
inject_vars_nix() {
    local partlabel="$1"
    cat > "$NIXOS_CONFIG_DIR/vars.nix" <<EOF
{
  username = "${USER_NAME}";
  userPassword = "${USER_PASS}";
  rootPassword = "${ROOT_PASS}";
  rootPartLabel = "${partlabel}";
}
EOF
    echo "  vars.nix: rootPartLabel=${partlabel}"
}

# --- 解析启动模式 ---
mapfile -t BOOT_MODES < <(parse_boot_modes "$BOOT_MODE") || exit 1

mkdir -p "$OUT_DIR"

# =========================================================================
# 主构建循环 — 每种启动模式独立构建 rootfs + boot.img
# =========================================================================
for MODE in "${BOOT_MODES[@]}"; do
    echo ""
    echo "======================================================"
    echo "Building: Mode=${MODE}"
    echo "======================================================"

    case "$MODE" in
        dual)   PARTLABEL="linux" ;;
        single) PARTLABEL="userdata" ;;
    esac

    # =====================================================================
    # Phase 1: RootFS 构建
    # =====================================================================
    echo "=== Phase 1: Building RootFS ==="

    inject_vars_nix "$PARTLABEL"

    echo "  Building Mobile NixOS rootfs: ${ROOTFS_FLAKE_ATTR}"
    OUT_LINK="$OUT_DIR/nixos-sheng-${ROOTFS_FLAKE_ATTR}"
    nix --extra-experimental-features "nix-command flakes" \
        build "./nixos#${ROOTFS_FLAKE_ATTR}" \
        --out-link "$OUT_LINK" \
        "${NIX_BUILD_FLAGS_ARRAY[@]}"

    ROOTFS_BUILD_DIR="$(readlink -f "$OUT_LINK")"
    ROOTFS_SOURCE="$(
        find "$ROOTFS_BUILD_DIR" -type f \( -name "rootfs.img" -o -name "rootfs.img.zst" \) 2>/dev/null | head -n 1
    )"

    if [ -z "${ROOTFS_SOURCE:-}" ] || [ ! -f "${ROOTFS_SOURCE:-}" ]; then
        echo "Error: rootfs image not found in $ROOTFS_BUILD_DIR" >&2
        exit 1
    fi

    ROOTFS_IMG="nixos-sheng-${MODE}-${TIMESTAMP}.img"

    echo "  Extracting make_ext4fs source image"
    SOURCE_IMG="${ROOTFS_IMG}.source"
    case "$ROOTFS_SOURCE" in
        *.zst)
            command -v zstd >/dev/null 2>&1 || { echo "Error: zstd required to decompress" >&2; exit 1; }
            zstd -dc "$ROOTFS_SOURCE" > "$OUT_DIR/$SOURCE_IMG"
            ;;
        *)
            cp "$ROOTFS_SOURCE" "$OUT_DIR/$SOURCE_IMG"
            ;;
    esac

    echo "  Mounting source and creating native ext4 image"
    SRC_MNT=$(mktemp -d)
    mount -o loop,ro "$OUT_DIR/$SOURCE_IMG" "$SRC_MNT"

    # Create fresh ext4 with native mkfs.ext4, bypassing make_ext4fs incompatibility
    SOURCE_SIZE="$(stat -c%s "$OUT_DIR/$SOURCE_IMG")"
    if [ "$IMAGE_SIZE" != "auto" ]; then
        TARGET_SIZE="$(numfmt --from=iec "$IMAGE_SIZE")"
    else
        # Add 256MB buffer for native ext4 metadata overhead vs make_ext4fs
        TARGET_SIZE=$((SOURCE_SIZE + 268435456))
    fi
    truncate -s "$TARGET_SIZE" "$OUT_DIR/$ROOTFS_IMG"
    mkfs.ext4 -L "$PARTLABEL" -U "$FILESYSTEM_UUID" -d "$SRC_MNT" "$OUT_DIR/$ROOTFS_IMG"

    umount "$SRC_MNT"
    rmdir "$SRC_MNT"
    rm -f "$OUT_DIR/$SOURCE_IMG"

    if [ "$IMAGE_SIZE" != "auto" ]; then
        echo "  Resizing to ${IMAGE_SIZE}"
        DESIRED_SIZE="$(numfmt --from=iec "$IMAGE_SIZE")"
        if [ "$DESIRED_SIZE" -lt "$TARGET_SIZE" ]; then
            resize2fs -f "$OUT_DIR/$ROOTFS_IMG" "$IMAGE_SIZE" || { echo "Error: resize2fs failed" >&2; exit 1; }
            truncate -s "$IMAGE_SIZE" "$OUT_DIR/$ROOTFS_IMG"
        fi
    else
        echo "  Shrinking to minimum size"
        resize2fs -fM "$OUT_DIR/$ROOTFS_IMG" || true
    fi

    echo "  Fixing fstab for ${PARTLABEL}"
    MNT_DIR=$(mktemp -d)
    mount -o loop "$OUT_DIR/$ROOTFS_IMG" "$MNT_DIR"
    mkdir -p "$MNT_DIR/etc"
    cat > "$MNT_DIR/etc/fstab" <<FSTABEOF
# Xiaomi Pad 6S Pro - NixOS rootfs
PARTLABEL=${PARTLABEL} / ext4 defaults,noatime,errors=remount-ro 0 1
FSTABEOF
    umount "$MNT_DIR"
    rmdir "$MNT_DIR"

    echo "  Verifying rootfs integrity"
    e2fsck -fn "$OUT_DIR/$ROOTFS_IMG" || echo "  WARNING: e2fsck reported issues"

    echo "  RootFS complete: $OUT_DIR/$ROOTFS_IMG"

    # =====================================================================
    # Phase 2: Boot 内核镜像编译
    # =====================================================================
    echo "=== Phase 2: Building Boot Kernel Image ==="
    BOOT_IMG_OK=0

    echo "  Building boot.img via Mobile NixOS..."
    NIX_ERR_FILE="$(mktemp)"
    if BOOT_OUT_PATH="$(
        nix --extra-experimental-features "nix-command flakes" \
            build "./nixos#mobileAndroidBootimg" \
            --no-link --print-out-paths \
            "${NIX_BUILD_FLAGS_ARRAY[@]}" 2>"$NIX_ERR_FILE"
    )" && [ -n "$BOOT_OUT_PATH" ]; then
        rm -f "$NIX_ERR_FILE"
        # Mobile NixOS 的 android-bootimg 输出可能是目录或单个文件
        if [ -f "$BOOT_OUT_PATH" ]; then
            cp "$BOOT_OUT_PATH" "$OUT_DIR/boot_sheng_${MODE}.img"
            echo "  Boot image: $OUT_DIR/boot_sheng_${MODE}.img"
            BOOT_IMG_OK=1
        elif [ -d "$BOOT_OUT_PATH" ]; then
            BOOT_IMG_CANDIDATE="$(find "$BOOT_OUT_PATH" -type f -name "*.img" 2>/dev/null | head -1)"
            if [ -n "${BOOT_IMG_CANDIDATE:-}" ] && [ -f "${BOOT_IMG_CANDIDATE:-}" ]; then
                cp "$BOOT_IMG_CANDIDATE" "$OUT_DIR/boot_sheng_${MODE}.img"
                echo "  Boot image: $OUT_DIR/boot_sheng_${MODE}.img"
                BOOT_IMG_OK=1
            fi
        else
            echo "  Error: unexpected Nix output: $BOOT_OUT_PATH" >&2
        fi
    else
        echo "  Mobile NixOS bootimg build failed:" >&2
        cat "$NIX_ERR_FILE" >&2
        rm -f "$NIX_ERR_FILE"
    fi

    if [ "$BOOT_IMG_OK" -eq 0 ]; then
        echo "  ERROR: boot image not generated for mode $MODE" >&2
    fi
done

echo ""
echo "[OK] NixOS image packaging complete!"
ls -lh "$OUT_DIR"/*.img 2>/dev/null || true
ls -lh "$OUT_DIR"/boot_sheng_*.img 2>/dev/null || true
