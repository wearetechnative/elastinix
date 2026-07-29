{ config, lib, pkgs, ... }:

let
  cfg = config.elastinix.services.hostinfo;

  # Detect all enabled elastinix services and programs at build time (pure)
  elastinixServices = lib.filterAttrs
    (n: v: lib.isAttrs v && (v.enable or false))
    (config.elastinix.services or {});

  elastinixPrograms = lib.filterAttrs
    (n: v: lib.isAttrs v && (v.enable or false))
    (config.elastinix.programs or {});

  # Static template without timestamp — timestamp injected at runtime
  staticTemplate = pkgs.writeText "hostinfo-static-template.json" (builtins.toJSON {
    hostname = config.networking.hostName;
    services = lib.mapAttrs (_n: _v: true) elastinixServices;
    programs = lib.mapAttrs (_n: _v: true) elastinixPrograms;
    nixosVersion = config.system.nixos.version or "unknown";
    systemStateVersion = config.system.stateVersion or "unknown";
  });

in {
  options.elastinix.services.hostinfo = {
    enable = lib.mkEnableOption "hostinfo HTTP server exposing system inventory JSON";

    port = lib.mkOption {
      type = lib.types.port;
      default = 3333;
      description = "Port for the hostinfo HTTP server";
    };

    enableVulnixReport = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Expose /var/lib/vulnix/output.json as vulnix-report.json via the hostinfo server";
    };

    enableInventory = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Generate services.json inventory via a daily systemd timer. Disable to run the HTTP server without inventory generation.";
    };

    enablePackages = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Expose /var/lib/packages/packages.json as packages.json via the hostinfo server. The source file is expected to be uploaded externally (e.g. by Terraform).";
    };

    enableDockerImages = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Generate a Docker image inventory from the Docker socket and expose it as docker-images.json via the hostinfo server.";
    };
  };

  config = lib.mkIf cfg.enable {

    systemd.tmpfiles.rules = [
      "d /var/lib/hostinfo 0755 root root -"
    ] ++ lib.optional cfg.enableVulnixReport
        "L+ /var/lib/hostinfo/vulnix-report.json - - - - /var/lib/vulnix/output.json"
      ++ lib.optional cfg.enablePackages
        "L+ /var/lib/hostinfo/packages.json - - - - /var/lib/packages/packages.json"
      ++ lib.optionals cfg.enableDockerImages [
        "d /var/lib/docker-inventory 0755 root docker -"
        "L+ /var/lib/hostinfo/docker-images.json - - - - /var/lib/docker-inventory/images.json"
      ];

    # Oneshot service: injects buildTime into static template and writes services.json
    systemd.services.elastinix-hostinfo-inventory = lib.mkIf cfg.enableInventory {
      description = "Generate elastinix hostinfo services.json";
      after = [ "systemd-tmpfiles-setup.service" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "oneshot";
        User = "root";
        Group = "root";
        ReadWritePaths = [ "/var/lib/hostinfo" ];
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

      script = ''
        BUILD_TIME=$(${pkgs.coreutils}/bin/date -u +%Y-%m-%dT%H:%M:%SZ)
        ${pkgs.jq}/bin/jq --arg buildTime "$BUILD_TIME" '. + {buildTime: $buildTime}' \
          ${staticTemplate} > /var/lib/hostinfo/services.json
        echo "Generated /var/lib/hostinfo/services.json at $BUILD_TIME"
      '';
    };

    # Daily timer for inventory regeneration
    systemd.timers.elastinix-hostinfo-inventory = lib.mkIf cfg.enableInventory {
      description = "Daily timer for elastinix hostinfo inventory generation";
      wantedBy = [ "timers.target" ];

      timerConfig = {
        OnCalendar = "daily";
        Persistent = true;
        RandomizedDelaySec = "1h";
      };
    };

    # Docker image inventory service and timer
    systemd.services.elastinix-docker-inventory = lib.mkIf cfg.enableDockerImages {
      description = "Generate elastinix Docker image inventory";
      after = [ "docker.service" "systemd-tmpfiles-setup.service" ];
      wants = [ "docker.service" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "oneshot";
        User = "root";
        Group = "docker";
        ReadWritePaths = [ "/var/lib/docker-inventory" ];
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        NoNewPrivileges = true;
        PrivateDevices = false;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectControlGroups = true;
        RestrictNamespaces = true;
        LockPersonality = true;
        RestrictRealtime = true;
        RestrictSUIDSGID = true;
        RemoveIPC = true;
      };

      script = ''
        ${pkgs.curl}/bin/curl --silent --unix-socket /var/run/docker.sock \
          http://localhost/images/json \
          | ${pkgs.jq}/bin/jq '[.[] | select(.RepoTags != null) | .RepoTags[] | select(. != "<none>:<none>") | {image: (split(":")[0]), tag: (split(":")[1] // "latest")}] | unique' \
          > /var/lib/docker-inventory/images.json
        echo "Generated /var/lib/docker-inventory/images.json"
      '';
    };

    systemd.timers.elastinix-docker-inventory = lib.mkIf cfg.enableDockerImages {
      description = "Daily timer for elastinix Docker image inventory generation";
      wantedBy = [ "timers.target" ];

      timerConfig = {
        OnCalendar = "daily";
        Persistent = true;
        RandomizedDelaySec = "1h";
      };
    };

    # Long-running HTTP server serving /var/lib/hostinfo/
    systemd.services.elastinix-hostinfo-server = {
      description = "Elastinix hostinfo HTTP server";
      after = [ "network.target" "systemd-tmpfiles-setup.service" ]
        ++ lib.optional cfg.enableInventory "elastinix-hostinfo-inventory.service";
      wants = lib.optional cfg.enableInventory "elastinix-hostinfo-inventory.service";
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "simple";
        ExecStart = "${pkgs.python3}/bin/python3 -m http.server ${toString cfg.port} --bind 0.0.0.0 --directory /var/lib/hostinfo";
        Restart = "always";
        RestartSec = "10s";
        User = "nobody";
        Group = "nogroup";

        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ProtectKernelTunables = true;
        ProtectControlGroups = true;
        ReadOnlyPaths = [ "/etc" "/var/lib/hostinfo" ];
      };
    };

    networking.firewall.allowedTCPPorts = [ cfg.port ];
  };
}
