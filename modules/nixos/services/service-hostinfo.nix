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

  inUseDir = "/var/lib/inuse-sampler";

  inUseSampler = pkgs.writeText "hostinfo-inuse-sampler.py" ''
    import json
    import os
    import re
    import tempfile
    from datetime import datetime, timezone

    DOC = "${inUseDir}/inuse.json"
    INTERVAL_SECONDS = ${toString cfg.inUseSamplerIntervalSeconds}
    SCHEMA_VERSION = 1

    # /nix/store/<32 chars>-<name>, capturing only <name> and stopping at the
    # first path separator, so a mapped library resolves to the package name
    # that owns it. The hash is deliberately excluded: consumers join this
    # against vulnix output, which is keyed by package name. Two builds of the
    # same name therefore merge, and if either is in use the name counts as in
    # use — the conservative direction.
    STORE = re.compile(r"/nix/store/[a-z0-9]{32}-([^/\s\x00\"';]+)")

    def read(path):
        try:
            with open(path, "rb") as fh:
                return fh.read().decode("utf-8", "replace")
        except (OSError, ValueError):
            return ""

    def unit_of(pid):
        for line in read(f"/proc/{pid}/cgroup").splitlines():
            m = re.search(r"([^/]+\.service)", line)
            if m:
                return m.group(1)
        return None

    def sample():
        """Map package name -> set of units observed holding it."""
        found = {}
        for pid in os.listdir("/proc"):
            if not pid.isdigit():
                continue
            blob = read(f"/proc/{pid}/maps")
            try:
                blob += "\n" + os.path.realpath(f"/proc/{pid}/exe")
            except OSError:
                pass
            blob += "\n" + read(f"/proc/{pid}/cmdline").replace("\0", "\n")
            names = set(STORE.findall(blob))
            if not names:
                continue
            unit = unit_of(pid)
            for name in names:
                entry = found.setdefault(name, set())
                if unit:
                    entry.add(unit)
        return found

    def main():
        now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
        try:
            with open(DOC) as fh:
                doc = json.load(fh)
        except (OSError, ValueError):
            doc = {}

        doc["schemaVersion"] = SCHEMA_VERSION
        doc["intervalSeconds"] = INTERVAL_SECONDS
        doc.setdefault("firstSample", now)
        doc["lastSample"] = now
        doc["sampleCount"] = int(doc.get("sampleCount", 0)) + 1
        observed = doc.setdefault("observed", {})

        current = sample()
        for name, units in current.items():
            entry = observed.setdefault(name, {})
            entry["samples"] = int(entry.get("samples", 0)) + 1
            entry["lastSeen"] = now
            entry["units"] = sorted(set(entry.get("units", [])) | units)

        # atomic replace: a crash mid-write must not destroy accumulated history
        fd, tmp = tempfile.mkstemp(dir=os.path.dirname(DOC), suffix=".tmp")
        try:
            with os.fdopen(fd, "w") as fh:
                json.dump(doc, fh, indent=1, sort_keys=True)
            # mkstemp creates 0600 and os.replace preserves it, which would
            # leave the document unreadable by the hostinfo HTTP server (it
            # runs as nobody) and serve a 404 despite the file existing.
            os.chmod(tmp, 0o644)
            os.replace(tmp, DOC)
        except BaseException:
            os.unlink(tmp)
            raise

        print(f"sample {doc['sampleCount']}: {len(current)} packages in use, "
              f"{len(observed)} observed cumulatively")

    if __name__ == "__main__":
        main()
  '';

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

    enableInUseSampler = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Periodically record which Nix store paths are mapped by running
        processes, accumulating into inuse.json and exposing it via the
        hostinfo server.
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

    systemd.tmpfiles.rules = [
      "d /var/lib/hostinfo 0755 root root -"
    ] ++ lib.optional cfg.enableVulnixReport
        "L+ /var/lib/hostinfo/vulnix-report.json - - - - /var/lib/vulnix/output.json"
      ++ lib.optional cfg.enablePackages
        "L+ /var/lib/hostinfo/packages.json - - - - /var/lib/packages/packages.json"
      ++ lib.optionals cfg.enableDockerImages [
        "d /var/lib/docker-inventory 0755 root docker -"
        "L+ /var/lib/hostinfo/docker-images.json - - - - /var/lib/docker-inventory/images.json"
      ]
      ++ lib.optionals cfg.enableInUseSampler [
        "d ${inUseDir} 0755 root root -"
        "L+ /var/lib/hostinfo/inuse.json - - - - ${inUseDir}/inuse.json"
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

    # In-use sampler: records which store paths running processes have mapped
    systemd.services.elastinix-inuse-sampler = lib.mkIf cfg.enableInUseSampler {
      description = "Sample Nix store paths in use by running processes";
      after = [ "systemd-tmpfiles-setup.service" ];

      serviceConfig = {
        Type = "oneshot";
        User = "root";
        Group = "root";
        ExecStart = "${pkgs.python3}/bin/python3 ${inUseSampler}";
        ReadWritePaths = [ inUseDir ];

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
        RestrictAddressFamilies = [ ];
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
