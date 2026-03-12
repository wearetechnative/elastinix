{ config, lib, pkgs, ... }:

with lib;

let
  cfg = config.services.jirasync;

  pythonEnv = pkgs.python3.withPackages (ps: with ps; [
    requests
  ]);

  jirasyncPackage = pkgs.stdenv.mkDerivation {
    pname = "jirasync";
    version = "1.0.0";

    src = ./.;

    nativeBuildInputs = [ pkgs.makeWrapper ];

    installPhase = ''
      mkdir -p $out/bin $out/share/jirasync

      # Install the Python script
      cp ../services-scripts/jirasync.py $out/share/jirasync/
      chmod +x $out/share/jirasync/jirasync.py

      # Create wrapper script
      makeWrapper ${pythonEnv}/bin/python3 $out/bin/jirasync \
        --add-flags "$out/share/jirasync/jirasync.py" \
        --add-flags "--config ${config.age.secrets.jirasync-config.path}" \
        --add-flags "--days ${toString cfg.daysToSync}" \
        ${optionalString cfg.dryRun "--add-flags --dry-run"}
    '';

    meta = with lib; {
      description = "Jira synchronization tool";
      license = licenses.mit;
      platforms = platforms.linux;
    };
  };

in {
  options.services.jirasync = {
    enable = mkEnableOption "Jira synchronization service";

    daysToSync = mkOption {
      type = types.int;
      default = 90;
      description = "Number of days to look back for issues";
    };

    dryRun = mkOption {
      type = types.bool;
      default = false;
      description = "Run in dry-run mode without making changes";
    };

    interval = mkOption {
      type = types.str;
      default = "hourly";
      description = "Systemd timer interval (e.g., 'daily', 'hourly', '*:0/30' for every 30 minutes)";
    };

    user = mkOption {
      type = types.str;
      default = "jirasync";
      description = "User to run the service as";
    };

    group = mkOption {
      type = types.str;
      default = "jirasync";
      description = "Group to run the service as";
    };
  };

  config = mkIf cfg.enable {
    # Create user and group
    users.users.${cfg.user} = {
      isSystemUser = true;
      group = cfg.group;
      description = "Jira sync service user";
    };

    users.groups.${cfg.group} = {};

    # Install the package
    environment.systemPackages = [ jirasyncPackage ];

    # Systemd service
    systemd.services.jirasync = {
      description = "Jira synchronization service";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];

      serviceConfig = {
        Type = "oneshot";
        User = cfg.user;
        Group = cfg.group;
        ExecStart = "${jirasyncPackage}/bin/jirasync";

        # Security hardening
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        NoNewPrivileges = true;
        PrivateDevices = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        RestrictAddressFamilies = [ "AF_INET" "AF_INET6" ];
        RestrictNamespaces = true;
        LockPersonality = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        RemoveIPC = true;
        SystemCallFilter = [ "@system-service" "~@privileged" ];
      };
    };

    # Systemd timer
    systemd.timers.jirasync = {
      description = "Timer for Jira synchronization";
      wantedBy = [ "timers.target" ];

      timerConfig = {
        OnCalendar = cfg.interval;
        Persistent = true;
        RandomizedDelaySec = "5min";
      };
    };
  };
}
