# ---
# Module: FastRPC Sensor
# Description: FastRPC configuration
# Scope: Host
# ---

{ lib, stdenv, fetchFromGitHub, autoreconfHook, pkg-config, libyaml, makeWrapper }:

stdenv.mkDerivation rec {
  pname = "fastrpc";
  version = "1.0.2";

  src = fetchFromGitHub {
    owner = "qualcomm";
    repo = "fastrpc";
    rev = "v${version}";
    hash = "sha256-/RXH34zqAxtWty75UHoOvS6fdmB+UfTRtB6G9IZiSWk=";
  };

  nativeBuildInputs = [ autoreconfHook pkg-config makeWrapper ];
  buildInputs = [ libyaml ];

  patches = [
    ./fastrpc-rflags.patch
  ];

  # Note: The original APKBUILD skips tests
  preAutoreconf = ''
    mkdir -p m4
  '';

  preConfigure = ''
    rm -rf src/fastrpc_test.c
    rm -rf src/fastrpc_test
  '';

  postInstall = ''
    # Clean up test binaries that might cause strip errors
    rm -rf $out/share/fastrpc_test
    rm -f $out/bin/fastrpc_test

    # Compile a simple client to keep a PD alive without registering a listener
    gcc -O2 -o $out/bin/fastrpc_keepalive -Iinc -Isrc -L$out/lib -ladsprpc \
      -Wl,-rpath,$out/lib \
      -xc - <<'EOF'
    #include <stdio.h>
    #include <unistd.h>
    #include "remote.h"
    #define ITRANSPORT_PREFIX "'\":;./\\"
    #define CREATE_STATICPD "createstaticpd:"
    int main(int argc, char **argv) {
        if (argc < 2) {
            printf("Usage: %s <uri_suffix>\n", argv[0]);
            return 1;
        }
        char name[256];
        snprintf(name, sizeof(name), "%s%s%s", ITRANSPORT_PREFIX, CREATE_STATICPD, argv[1]);
        remote_handle64 fd;
        if (remote_handle64_open(name, &fd) == 0) {
            printf("Handle opened for %s. Sleeping forever.\n", name);
            while (1) pause();
        } else {
            printf("Failed to open handle for %s.\n", name);
            return 1;
        }
        return 0;
    }
    EOF

    # Wrap binaries so dlopen can confidently find the listener libraries
    for p in adsprpcd cdsprpcd sdsprpcd gdsprpcd; do
      if [ -f $out/bin/$p ]; then
        wrapProgram $out/bin/$p \
          --prefix LD_LIBRARY_PATH : "$out/lib"
      fi
    done
  '';

  meta = with lib; {
    description = "FastRPC Daemon for Qualcomm ADSP";
    homepage = "https://github.com/qualcomm/fastrpc";
    license = licenses.bsd3;
    platforms = platforms.linux;
  };
}
