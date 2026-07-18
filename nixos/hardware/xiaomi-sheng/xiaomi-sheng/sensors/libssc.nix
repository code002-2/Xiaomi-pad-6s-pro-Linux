# ---
# Module: LibSSC Sensor
# Description: LibSSC configuration
# Scope: Host
# ---

{ lib, stdenv, meson, ninja, pkg-config, glib, protobufc, protobuf, libqmi, libmbim }:

stdenv.mkDerivation {
  pname = "libssc";
  version = "0.3.0";

  src = ../../../vendor/libssc;

  patches = [
    ./wait_for_qmi_service.patch
  ];

  nativeBuildInputs = [ meson ninja pkg-config protobufc protobuf ];
  buildInputs = [ glib protobufc libqmi libmbim ];

  meta = with lib; {
    description = "Library to expose Qualcomm Sensor Core sensors";
    # Most vendored source files identify themselves as AGPL-3.0-or-later.
    license = licenses.agpl3Plus;
    platforms = platforms.linux;
  };
}
