# ---
# Module: DevAuth Sensor
# Description: Devauth sensor configuration
# Scope: Host
# ---

{ stdenv
, lib
, fetchurl
, patchelf
}:

# xiaomi_devauth is a precompiled aarch64 binary for Xiaomi sensor/keyboard authentication.
# We fetch it directly from the sheng-firmware-full repository to avoid flake.lock sync issues.
stdenv.mkDerivation {
  pname = "xiaomi-devauth";
  version = "1.0.0";

  src = fetchurl {
    url = "https://raw.githubusercontent.com/DotRedstone/sheng-firmware-full/main/bin/xiaomi_devauth";
    sha256 = "b814988c0aaef534121a8234796e85118fa07259479eb2f3fae72a953d91752f";
  };

  nativeBuildInputs = [
    patchelf
  ];

  # No build required — this is a precompiled binary
  dontUnpack = true;
  dontBuild = true;
  dontStrip = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin
    cp $src $out/bin/xiaomi_devauth
    chmod +wx $out/bin/xiaomi_devauth
    
    patchelf \
      --set-interpreter "$(cat $NIX_CC/nix-support/dynamic-linker)" \
      --set-rpath "${lib.makeLibraryPath [ stdenv.cc.libc stdenv.cc.cc.lib ]}" \
      $out/bin/xiaomi_devauth
      
    runHook postInstall
  '';

  meta = with lib; {
    description = "Xiaomi Proprietary Sensor and Keyboard Authentication Daemon";
    platforms = [ "aarch64-linux" ];
    license = licenses.unfree;
  };
}
