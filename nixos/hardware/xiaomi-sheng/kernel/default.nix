# ---
# Module: Kernel Config (Sheng)
# Description: Custom kernel and patches for xiaomi-sheng
# Scope: Host
# ---

{ mobile-nixos
, shengKernelSrc
, buildPackages
, ...
}:

let
  pkgs = buildPackages;
  llvmPkgs = pkgs.llvmPackages;
in
mobile-nixos.kernel-builder-clang {
  version = "7.1.3";
  modDirVersion = "7.1.3";
  src = shengKernelSrc;
  configfile = ./config.aarch64;
  patches = [
    ./0001-disable-dp0-sheng.patch
    # 0002/0003 conflict with sheng-7.1.3 (debug-only, upstreamed)
    # ./0002-ucsi-glink-debug-retry.patch
    # ./0003-pdr-pd-mapper-debug.patch
    ./0004-pdr-add-sheng-sensor-pd-lookup.patch
    # b6c3859 patch is already applied in sheng-7.1.3 — skip it
  ];

  isModular = true;
  isCompressed = "gz";
  isImageGzDtb = false;
  enableRemovingWerror = true;
  nativeBuildInputs = [
    buildPackages.lld
    buildPackages.llvmPackages.clang
    buildPackages.llvmPackages.llvm
    pkgs.buildPackages.python3
    pkgs.buildPackages.zstd
  ];
  makeFlags = [
    "LLVM=1"
    "CC=${llvmPkgs.clang-unwrapped}/bin/clang"
    "LD=${pkgs.lld}/bin/ld.lld"
    "AR=${llvmPkgs.llvm}/bin/llvm-ar"
    "NM=${llvmPkgs.llvm}/bin/llvm-nm"
    "OBJCOPY=${llvmPkgs.llvm}/bin/llvm-objcopy"
    "OBJDUMP=${llvmPkgs.llvm}/bin/llvm-objdump"
    "READELF=${llvmPkgs.llvm}/bin/llvm-readelf"
    "STRIP=${llvmPkgs.llvm}/bin/llvm-strip"
    "KCFLAGS=-Wno-error=unused-command-line-argument"
    "KCPPFLAGS=-Wno-error=unused-command-line-argument"
  ];

  postConfigure = ''
    echo "===== effective kernel config diagnostics ====="

    echo "--- io_uring ---"
    grep -nE '^CONFIG_IO_URING=|^# CONFIG_IO_URING is not set' build/.config || true

    echo "--- rootfs essentials ---"
    grep -nE '^CONFIG_EXT4_FS=|^CONFIG_BLK_DEV_INITRD=|^CONFIG_DEVTMPFS=|^CONFIG_TMPFS=' build/.config || true

    echo "--- compat / neon ---"
    grep -nE '^CONFIG_COMPAT=|^# CONFIG_COMPAT is not set|^CONFIG_COMPAT_VDSO=|^# CONFIG_COMPAT_VDSO is not set|^CONFIG_KUSER_HELPERS=|^# CONFIG_KUSER_HELPERS is not set|^CONFIG_KERNEL_MODE_NEON=|^# CONFIG_KERNEL_MODE_NEON is not set' build/.config || true

    echo "--- gpio shared proxy ---"
    grep -nE '^CONFIG_HAVE_SHARED_GPIOS=|^CONFIG_GPIO_SHARED=|^CONFIG_GPIO_SHARED_PROXY=' build/.config || true

    echo "--- mobile-nixos network validation related ---"
    grep -nE '^CONFIG_BRIDGE=|^CONFIG_BRIDGE_NETFILTER=|^CONFIG_NF_TABLES=|^CONFIG_NETFILTER_XTABLES=|^CONFIG_IP6_NF_IPTABLES=' build/.config || true

    echo "--- general-purpose userspace and filesystems ---"
    grep -nE '^CONFIG_BPF_SYSCALL=|^CONFIG_BPF_UNPRIV_DEFAULT_OFF=|^CONFIG_CGROUP_BPF=|^CONFIG_IO_URING=|^CONFIG_ZRAM=|^CONFIG_ZRAM_DEF_COMP=|^CONFIG_FUSE_FS=|^CONFIG_OVERLAY_FS=|^CONFIG_SQUASHFS=|^CONFIG_EROFS_FS=|^CONFIG_NFS_FS=|^CONFIG_NFS_V3=|^CONFIG_NFS_V4=|^CONFIG_CIFS=' build/.config || true

    echo "--- usb/input config ---"
    grep -nE '^(CONFIG_USB=|CONFIG_USB_COMMON=|CONFIG_USB_XHCI_HCD=|CONFIG_USB_XHCI_PLATFORM=|CONFIG_USB_DWC3=|CONFIG_USB_DWC3_QCOM=|CONFIG_USB_ROLE_SWITCH=|CONFIG_TYPEC=|CONFIG_TYPEC_UCSI=|CONFIG_UCSI_PMIC_GLINK=|CONFIG_QCOM_PMIC_GLINK=|CONFIG_QCOM_PMIC_GLINK_ALT_MODE=|CONFIG_QCOM_PDR_HELPERS=|CONFIG_QCOM_PD_MAPPER=|CONFIG_QRTR=|CONFIG_HID=|CONFIG_HID_GENERIC=|CONFIG_USB_HID=|CONFIG_INPUT_EVDEV=|CONFIG_USB_STORAGE=)' build/.config || true

    echo "--- qcom typec/pdr config ---"
    grep -nE '^CONFIG_QRTR=|^CONFIG_QCOM_PD_MAPPER=|^CONFIG_QCOM_PDR_HELPERS=|^CONFIG_QCOM_PMIC_GLINK=|^CONFIG_UCSI_PMIC_GLINK=|^CONFIG_TYPEC_UCSI=|^CONFIG_USB_ROLE_SWITCH=' build/.config || true

    echo "--- pmic glink power supply config ---"
    grep -nE '^CONFIG_POWER_SUPPLY=|^CONFIG_BATTERY_QCOM_BATTMGR=|^CONFIG_QCOM_PMIC_GLINK=|^CONFIG_UCSI_PMIC_GLINK=|^CONFIG_TYPEC_UCSI=|^CONFIG_TYPEC=|^CONFIG_QRTR=|^CONFIG_QCOM_PD_MAPPER=' build/.config || true

    echo "--- Xiaomi MiPPS hooks ---"
    grep -nE 'BATTMGR_XM_PROPERTY_GET|request_vdm_cmd|qcom_battmgr_xiaomi_attr_group' drivers/power/supply/qcom_battmgr.c || true

    echo "--- compiler identity ---"
    command -v clang || true
    clang --version | head -3 || true
    clang -print-target-triple || true
    clang -print-resource-dir || true
  '';
}
