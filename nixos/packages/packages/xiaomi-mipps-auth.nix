# ---
# Module: Xiaomi MIPPS Auth Package
# Description: Xiaomi specific authentication package
# Scope: Package
# ---

{
  fetchurl,
  lib,
  python3,
  stdenvNoCC,
}:

stdenvNoCC.mkDerivation {
  pname = "xiaomi-mipps-auth";
  version = "0.11-51e2de3";

  src = fetchurl {
    url = "https://raw.githubusercontent.com/ianchb/xiaomi-mipps-auth/51e2de38070a5d6cbef59c7dbb05537dd9c14e27/xiaomi-mipps-auth";
    hash = "sha256-zuMLuRPOV8R3Zhg8dj7H41uRLODB9ilLVcGckZMoUOA=";
  };

  dontUnpack = true;
  nativeBuildInputs = [ python3 ];

  installPhase = ''
    runHook preInstall

    install -Dm0755 "$src" "$out/bin/xiaomi-mipps-auth"
    patchShebangs "$out/bin/xiaomi-mipps-auth"

    runHook postInstall
  '';

  meta = {
    description = "Automatic Xiaomi MiPPS/PPS charger authentication for sheng";
    homepage = "https://github.com/ianchb/xiaomi-mipps-auth";
    license = lib.licenses.gpl2Only;
    platforms = [ "aarch64-linux" ];
    mainProgram = "xiaomi-mipps-auth";
  };
}
