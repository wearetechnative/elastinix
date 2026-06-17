{ config, lib, pkgs, ... }:

let
  cfg = config.elastinix.services.vulnix-scan;

in {
  options.elastinix.services.vulnix-scan = {
    enable = lib.mkEnableOption "weekly vulnerability scanning with vulnix";
  };

  config = lib.mkIf cfg.enable {
    systemd.tmpfiles.rules = [
      "d /var/lib/sbom 0755 root root -"
    ];

    systemd.services.vulnix-scan = {
      description = "Scan NixOS system closure for known vulnerabilities";

      script = ''
      
        echo "Scanning packages for known CVEs..."
        ${pkgs.vulnix}/bin/vulnix --cache-dir /var/lib/sbom/cache --from-file /var/lib/sbom/packages.json > /var/lib/sbom/output.json || EXIT=$?

      '';

      serviceConfig = {
        Type = "oneshot";
        User = "root";
        Group = "root";

        ReadWritePaths = [ "/var/lib/sbom" ];

        # Security hardening
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        NoNewPrivileges = true;
        PrivateDevices = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        RestrictNamespaces = true;
        LockPersonality = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        RemoveIPC = true;
      };
    };

    systemd.timers.vulnix-scan = {
      description = "Weekly timer for vulnix vulnerability scan";
      wantedBy = [ "timers.target" ];

      timerConfig = {
        OnCalendar = "weekly";
        Persistent = true;
        RandomizedDelaySec = "6h";
      };
    };
  };
}