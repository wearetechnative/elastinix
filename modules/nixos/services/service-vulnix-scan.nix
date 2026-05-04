{ config, lib, pkgs, ... }:

let
  cfg = config.elastinix.services.vulnix-scan;

  generatePackagesJson = pkgs.writeScript "generate-vulnix-packages-json" ''
    #!${pkgs.python3}/bin/python3
    import json, subprocess, os, re

    result = subprocess.run(
        ["${pkgs.nix}/bin/nix-store", "-qR", "/run/current-system"],
        capture_output=True, text=True
    )
    paths = result.stdout.strip().split("\n")

    packages = {}
    for i, path in enumerate(paths):
        basename = os.path.basename(path)
        name = re.sub(r"^[a-z0-9]{32}-", "", basename)
        if name:
            packages[f"pkg{i}"] = {"name": name, "patches": []}

    with open("/var/lib/sbom/packages.json", "w") as f:
        json.dump(packages, f)
  '';
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
        echo "Generating package manifest from /run/current-system..."
        ${generatePackagesJson}

        echo "Scanning packages for known CVEs..."
        ${pkgs.vulnix}/bin/vulnix --json --cache-dir /var/lib/sbom/cache --from-file /var/lib/sbom/packages.json --no-requisites > /var/lib/sbom/system.json || EXIT=$?

        if [ "''${EXIT:-0}" -eq 2 ]; then
          echo "Vulnerabilities found. See /var/lib/sbom/system.json for details."
          echo "Review with: journalctl -u vulnix-scan or cat /var/lib/sbom/system.json | jq ."
          exit 0
        elif [ "''${EXIT:-0}" -ne 0 ]; then
          echo "vulnix exited with unexpected code $EXIT"
          exit 0
        else
          echo "No known vulnerabilities found."
        fi
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
