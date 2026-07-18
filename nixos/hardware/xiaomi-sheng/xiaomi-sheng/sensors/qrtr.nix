# ---
# Module: QRTR Sensor
# Description: QRTR routing configuration
# Scope: Host
# ---

{ lib, stdenv, fetchurl, meson, ninja, pkg-config }:

stdenv.mkDerivation rec {
  pname = "qrtr";
  version = "1.2";

  src = fetchurl {
    url = "https://github.com/linux-msm/qrtr/archive/ae881086dfd29f828dcadb56e4b32a09fdc5c202.tar.gz";
    sha256 = "d990ca5160384c8051b096a1f72db3b8163dc22e94b7be628ff7c2ebcd0c7f31";
  };

  nativeBuildInputs = [ meson ninja pkg-config ];

  meta = with lib; {
    description = "Qualcomm IPC Router utility libraries";
    license = licenses.bsd3;
    platforms = platforms.linux;
  };
}
