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

  # The HTTP-served directory is also where state lives: a writer puts its
  # document where it is served, so nothing has to be symlinked into place. Only
  # documents this host does not own stay symlinks -- see the tmpfiles rules.
  hostinfoDir = "/var/lib/hostinfo";

  inUseSampler = pkgs.writeText "hostinfo-runtime-sampler.py"
    (builtins.readFile ./hostinfo-runtime-sampler.py);

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
      description = ''
        Expose /var/lib/packages/packages.json as packages.json via the hostinfo
        server. The source file is written externally (e.g. by Terraform).

        This one stays a symlink deliberately. Every other document is written by
        a service in this module, which can simply write where it is served; this
        one is produced by a system outside NixOS entirely, so the link is the
        interface between where that system uploads and where we serve from.
      '';
    };

    enableDockerImages = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Generate a Docker image inventory from the Docker socket and expose it as docker-images.json via the hostinfo server.";
    };

    enableInUseSampler = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Periodically record which Nix store paths are mapped by running
        processes into a daily record, exposed under observations/ by the
        hostinfo server. A day is sealed when it rolls over and never
        modified again.
      '';
    };

    enableSocketObservation = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Also record listening sockets, their bind address, and the user each
        observed unit runs as, into the same daily record.

        Bind address is the point: a service bound to loopback is unreachable
        from anywhere else whatever the security group says, and neither the Nix
        configuration nor the AWS API can tell you which address a process bound
        to. Requires enableInUseSampler, since it is the same sampler run.
      '';
    };

    inUseSamplerGapIntervals = lib.mkOption {
      type = lib.types.ints.positive;
      default = 2;
      description = ''
        How many sampler intervals a gap may span before it counts as a sample that
        should have been taken and was not.

        Observation is recorded per day. A gap within this many intervals is credited
        as observed; a longer one means a sample was missed, and the host's own
        uptime decides whose fault that was. Uptime shorter than the gap means the
        machine rebooted, so the missing time is downtime and no observation was
        owed. Uptime longer means the machine was running while nothing sampled it,
        which leaves the day incomplete.

        Two intervals leaves room for the timer's own accuracy without hiding a
        genuinely missed sample. Raising it hides missed samples; lowering it to one
        would report ordinary jitter as unobserved time.
      '';
    };

    inUseSamplerIntervalSeconds = lib.mkOption {
      type = lib.types.ints.positive;
      default = 300;
      description = ''
        Seconds between in-use samples.
      '';
    };
  };

  config = lib.mkIf cfg.enable {

    assertions = [
      {
        assertion = cfg.enableSocketObservation -> cfg.enableInUseSampler;
        message = ''
          elastinix.services.hostinfo.enableSocketObservation requires
          enableInUseSampler: socket observation is collected by the same
          sampler run.
        '';
      }
    ];

    systemd.tmpfiles.rules = [
      "d ${hostinfoDir} 0755 root root -"
    ]
      # The two documents this module does not write. The central scanner owns
      # /var/lib/vulnix, and packages.json is uploaded by Terraform, so both stay
      # links rather than being served from where their owner happens to put them.
      ++ lib.optional cfg.enableVulnixReport
        "L+ ${hostinfoDir}/vulnix-report.json - - - - /var/lib/vulnix/output.json"
      ++ lib.optional cfg.enablePackages
        "L+ ${hostinfoDir}/packages.json - - - - /var/lib/packages/packages.json"
      ++ lib.optionals cfg.enableInUseSampler [
        # Served as a directory rather than named files: a consumer lists it and
        # fetches the days it does not have, so nothing here has to know which
        # dates exist.
        "d ${hostinfoDir}/observations 0755 root root -"
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
        ReadWritePaths = [ hostinfoDir ];
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
        # Written via a temporary file: the destination is served over HTTP, so a
        # truncating redirect would let a consumer fetch an empty inventory
        # mid-write and read it as "no images".
        TMP=$(${pkgs.coreutils}/bin/mktemp ${hostinfoDir}/.docker-images.XXXXXX)
        ${pkgs.curl}/bin/curl --silent --unix-socket /var/run/docker.sock \
          http://localhost/images/json \
          | ${pkgs.jq}/bin/jq '[.[] | select(.RepoTags != null) | .RepoTags[] | select(. != "<none>:<none>") | {image: (split(":")[0]), tag: (split(":")[1] // "latest")}] | unique' \
          > "$TMP"
        ${pkgs.coreutils}/bin/chmod 644 "$TMP"
        ${pkgs.coreutils}/bin/mv "$TMP" ${hostinfoDir}/docker-images.json
        echo "Generated ${hostinfoDir}/docker-images.json"
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

    # In-use sampler: records which store paths running processes have mapped
    systemd.services.elastinix-inuse-sampler = lib.mkIf cfg.enableInUseSampler {
      description = "Sample Nix store paths, listening sockets and unit users";
      after = [ "systemd-tmpfiles-setup.service" ];

      serviceConfig = {
        Type = "oneshot";
        User = "root";
        Group = "root";
        ExecStart = lib.concatStringsSep " " [
          "${pkgs.python3}/bin/python3"
          "${inUseSampler}"
          "--hostinfo-dir ${hostinfoDir}"
          "--interval-seconds ${toString cfg.inUseSamplerIntervalSeconds}"
          "--gap-intervals ${toString cfg.inUseSamplerGapIntervals}"
          "--observe-sockets ${if cfg.enableSocketObservation then "1" else "0"}"
          "--ss ${pkgs.iproute2}/bin/ss"
        ];
        ReadWritePaths = [ "${hostinfoDir}/observations" ];

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
        RestrictAddressFamilies =
          lib.optional cfg.enableSocketObservation "AF_NETLINK";
      };
    };

    systemd.timers.elastinix-inuse-sampler = lib.mkIf cfg.enableInUseSampler {
      description = "Timer for the Nix store in-use sampler";
      wantedBy = [ "timers.target" ];

      timerConfig = {
        OnBootSec = "2min";
        OnUnitActiveSec = "${toString cfg.inUseSamplerIntervalSeconds}s";
        AccuracySec = "30s";
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
