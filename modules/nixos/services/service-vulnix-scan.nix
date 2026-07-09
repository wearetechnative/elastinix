{ config, lib, pkgs, ... }:

let
  cfg = config.elastinix.services.vulnix-scan;
in {
  options.elastinix.services.vulnix-scan = {
    enable = lib.mkEnableOption "weekly vulnerability scanning with vulnix";
  };

  config = lib.mkIf cfg.enable {
    systemd.tmpfiles.rules = [
      "d /var/lib/packages 0755 root root -"
      "d /var/lib/vulnix 0755 root root -"
    ];

    systemd.services.vulnix-scan = {
      description = "Scan NixOS system closure for known vulnerabilities";

      path = [ pkgs.util-linux pkgs.coreutils ];

      script = ''
        # Check if packages.json is available (uploaded by deploy-wrapper)
        if [ ! -f /var/lib/packages/packages.json ]; then
          echo "WARNING: /var/lib/packages/packages.json not found. Skipping scan."
          echo "packages.json must be uploaded by the deploy-wrapper before the first scan."
          exit 0
        fi

        # Bootstrap detection: check if NVD cache is empty or corrupted (Data.fs < 1MB)
        BOOTSTRAP=false
        DATAFS=/var/lib/vulnix/cache/Data.fs
        DATAFS_SIZE=$(stat -c%s "$DATAFS" 2>/dev/null || echo 0)
        if [ ! -f "$DATAFS" ] || [ "$DATAFS_SIZE" -lt 1048576 ]; then
          BOOTSTRAP=true
        fi

        if [ "$BOOTSTRAP" = "true" ]; then
          echo "Bootstrap mode: NVD cache is empty or too small (''${DATAFS_SIZE} bytes), checking disk space..."

          # Check available disk space on /var/lib/vulnix (need at least 2GB)
          AVAIL=$(df --output=avail /var/lib/vulnix | tail -1)
          AVAIL_MB=$((AVAIL / 1024))
          echo "Available disk space: ''${AVAIL_MB}MB"

          if [ "$AVAIL_MB" -lt 2048 ]; then
            echo "WARNING: Less than 2GB available on /var/lib/vulnix (''${AVAIL_MB}MB). Skipping bootstrap."
            echo "Free up disk space and run again to initialize the NVD cache."
            exit 0
          fi

          echo "Creating 1.5GB swapfile for NVD cache initialization..."
          dd if=/dev/zero of=/var/lib/vulnix/swap bs=1M count=1500 status=progress
          chmod 600 /var/lib/vulnix/swap
          mkswap /var/lib/vulnix/swap
          swapon /var/lib/vulnix/swap
          echo "Swapfile activated."
        fi

        echo "Scanning packages for known CVEs..."
        ${pkgs.vulnix}/bin/vulnix --json --cache-dir /var/lib/vulnix/cache --from-file /var/lib/packages/packages.json --no-requisites > /var/lib/vulnix/output.json || EXIT=$?

        if [ "$BOOTSTRAP" = "true" ]; then
          echo "Bootstrap complete. Removing swapfile..."
          swapoff /var/lib/vulnix/swap || true
          rm -f /var/lib/vulnix/swap
          echo "Swapfile removed."
        fi

        if [ "''${EXIT:-0}" -eq 2 ]; then
          echo "Vulnerabilities found. See /var/lib/vulnix/output.json for details."
          echo "Review with: journalctl -u vulnix-scan or cat /var/lib/vulnix/output.json | jq ."
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

        ExecStopPost = "${pkgs.bash}/bin/bash -c 'swapoff /var/lib/vulnix/swap || true; rm -f /var/lib/vulnix/swap'";

        ReadWritePaths = [ "/var/lib/packages" "/var/lib/vulnix" ];

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
