# ---
# Module: Sensors File
# Description: Sensors file definition
# Scope: Host
# ---

{ lib, stdenv, fetchFromGitHub }:

stdenv.mkDerivation rec {
  pname = "sheng-sensors-file";
  version = "main";

  src = fetchFromGitHub {
    owner = "alghiffaryfa19";
    repo = "sheng-sensors-file";
    rev = "main";
    hash = "sha256-yXX8QUxQ45yS0zCkpXQneiOhinOVCZrjNJVc824dHqQ=";
  };

  installPhase = ''
    mkdir -p $out
    cp -a usr/* $out/
  '';

  meta = with lib; {
    description = "Sensor configuration files for Xiaomi Pad 6S Pro (sheng)";
    # Upstream currently publishes no license. Do not imply permission that
    # the upstream author has not granted.
    license = licenses.unfree;
    platforms = platforms.linux;
  };
}
