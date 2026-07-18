# ---
# Module: Sheng DevAuth Service
# Description: Systemd service for devauth
# Scope: Service
# ---

{ config, lib, pkgs, ... }:

let
  cfg = config.services.sheng-devauth;
in
{
  options.services.sheng-devauth = {
    enable = lib.mkEnableOption "Xiaomi keyboard authentication service";

    package = lib.mkOption {
      type = lib.types.nullOr lib.types.package;
      default = null;
      description = "Package that provides the xiaomi_devauth binary.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.package != null;
        message = "services.sheng-devauth.package must provide xiaomi_devauth.";
      }
    ];

    systemd.services.sheng-devauth = {
      description = "Xiaomi DevAuth Service";
      wantedBy = [ "sysinit.target" ];
      after = [ "local-fs.target" ];
      serviceConfig = {
        Type = "simple";
        ExecStart = "${cfg.package}/bin/xiaomi_devauth";
        Restart = "on-failure";
        RestartSec = "5s";
      };
    };
  };
}
