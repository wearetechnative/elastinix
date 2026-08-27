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

  inUseSampler = pkgs.writeText "hostinfo-runtime-sampler.py" ''
    import json
    import os
    import pwd
    import re
    import subprocess
    import tempfile
    from datetime import datetime, timezone

    STATE = "${inUseDir}/runtime-facts.json"
    INUSE = "${inUseDir}/inuse.json"
    INTERVAL_SECONDS = ${toString cfg.inUseSamplerIntervalSeconds}
    SCHEMA_VERSION = 1
    OBSERVE_SOCKETS = ${if cfg.enableSocketObservation then "True" else "False"}
    SS = "${pkgs.iproute2}/bin/ss"

    # /nix/store/<32 chars>-<name>, capturing only <name> and stopping at the first
    # path separator, so a mapped library resolves to the package name that owns it.
    # The hash is deliberately excluded: consumers join this against vulnix output,
    # which is keyed by package name. Two builds of the same name therefore merge,
    # and if either is in use the name counts as in use -- the conservative
    # direction.
    STORE = re.compile(r"/nix/store/[a-z0-9]{32}-([^/\s\x00\"';]+)")
    PID_RE = re.compile(r"pid=(\d+)")

    WILDCARD_ADDRS = {"0.0.0.0", "::", "*"}


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


    def user_of(pid):
        for line in read(f"/proc/{pid}/status").splitlines():
            if line.startswith("Uid:"):
                try:
                    uid = int(line.split()[1])
                except (IndexError, ValueError):
                    return None
                try:
                    return pwd.getpwuid(uid).pw_name
                except KeyError:
                    return str(uid)
        return None


    def normalize_addr(addr):
        """Strip the scope suffix and unwrap IPv4-mapped IPv6.

        ss reports both "127.0.0.53%lo" and "::ffff:127.0.0.1". The second is an
        IPv4-mapped IPv6 address for a loopback listener; classifying it as
        "specific" would cost us the strongest claim available -- that nothing off
        this machine can reach it at all.
        """
        addr = addr.split("%", 1)[0]
        if addr.lower().startswith("::ffff:"):
            addr = addr[len("::ffff:"):]
        return addr


    def bind_class(addr):
        """loopback / wildcard / specific.

        The IPv6 wildcard counts as wildcard, not as an IPv6-only bind: such a
        socket accepts IPv4 connections too unless v6only is set, so calling it
        anything else would understate reachability.
        """
        plain = normalize_addr(addr)
        if plain in WILDCARD_ADDRS:
            return "wildcard"
        if plain.startswith("127.") or plain == "::1":
            return "loopback"
        return "specific"


    def split_hostport(text):
        if text.startswith("["):
            host, _, port = text.rpartition("]:")
            return host[1:], port
        host, _, port = text.rpartition(":")
        return host, port


    def sample_processes():
        """Package name -> units observed holding it, and unit -> users."""
        packages = {}
        unit_users = {}
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
            unit = unit_of(pid)
            if unit:
                user = user_of(pid)
                if user:
                    unit_users.setdefault(unit, set()).add(user)
            for name in names:
                entry = packages.setdefault(name, set())
                if unit:
                    entry.add(unit)
        return packages, unit_users


    def sample_sockets():
        """Listening sockets, keeping the raw address beside its class."""
        # ss queries sock_diag over netlink. If the unit denied AF_NETLINK this
        # would yield nothing while still exiting successfully -- the same
        # silent-blindness failure as hiding /proc -- so failure must be loud.
        out = subprocess.run(
            [SS, "-lntupH"], check=True, capture_output=True, text=True
        ).stdout
        sockets = []
        for line in out.splitlines():
            fields = line.split()
            if len(fields) < 5:
                continue
            proto = fields[0]
            if proto not in ("tcp", "udp"):
                continue
            addr, port = split_hostport(fields[4])
            if not port.isdigit():
                continue
            unit = None
            user = None
            for pid in PID_RE.findall(line):
                unit = unit or unit_of(pid)
                user = user or user_of(pid)
            sockets.append({
                "port": int(port),
                "proto": proto,
                "address": addr,
                "bindClass": bind_class(addr),
                "unit": unit,
                "user": user,
            })
        return sockets


    def seed_from_inuse():
        """Carry accumulated history across the move to runtime-facts.json.

        The in-use document can hold months of samples. Starting from zero would
        discard the observation window that every "never observed" claim depends on,
        silently weakening the evidence rather than failing.
        """
        try:
            with open(INUSE) as fh:
                old = json.load(fh)
        except (OSError, ValueError):
            return {}
        doc = {"inuse": {"observed": old.get("observed", {})}}
        for key in ("firstSample", "lastSample", "sampleCount"):
            if key in old:
                doc[key] = old[key]
        return doc


    def load_state(now):
        try:
            with open(STATE) as fh:
                doc = json.load(fh)
        except (OSError, ValueError):
            doc = seed_from_inuse()
        doc["intervalSeconds"] = INTERVAL_SECONDS
        doc.setdefault("firstSample", now)
        doc.setdefault("sampleCount", 0)
        doc.setdefault("inuse", {}).setdefault("observed", {})
        sockets = doc.setdefault("sockets", {})
        sockets.setdefault("observed", {})
        sockets.setdefault("current", [])
        doc.setdefault("units", {}).setdefault("user", {})
        return doc


    def write_json(path, payload):
        # atomic replace: a crash mid-write must not destroy accumulated history
        fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path), suffix=".tmp")
        try:
            with os.fdopen(fd, "w") as fh:
                json.dump(payload, fh, indent=1, sort_keys=True)
            # mkstemp creates 0600 and os.replace preserves it, which would leave
            # the document unreadable by the hostinfo HTTP server (it runs as
            # nobody) and serve a 404 despite the file existing.
            os.chmod(tmp, 0o644)
            os.replace(tmp, path)
        except BaseException:
            os.unlink(tmp)
            raise


    def project_inuse(doc):
        """The original document shape, so existing consumers keep working."""
        return {
            "schemaVersion": 1,
            "intervalSeconds": doc["intervalSeconds"],
            "firstSample": doc["firstSample"],
            "lastSample": doc["lastSample"],
            "sampleCount": doc["sampleCount"],
            "observed": doc["inuse"]["observed"],
        }


    def main():
        now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
        doc = load_state(now)

        doc["schemaVersion"] = SCHEMA_VERSION
        doc["lastSample"] = now
        doc["sampleCount"] = int(doc.get("sampleCount", 0)) + 1

        packages, unit_users = sample_processes()

        observed = doc["inuse"]["observed"]
        for name, units in packages.items():
            entry = observed.setdefault(name, {})
            entry["samples"] = int(entry.get("samples", 0)) + 1
            entry["lastSeen"] = now
            entry["units"] = sorted(set(entry.get("units", [])) | units)

        users_map = doc["units"]["user"]
        for unit, users in unit_users.items():
            users_map[unit] = sorted(set(users_map.get(unit, [])) | users)

        sockets = []
        if OBSERVE_SOCKETS:
            sockets = sample_sockets()
            sock_observed = doc["sockets"]["observed"]
            for sock in sockets:
                key = "%d/%s/%s" % (sock["port"], sock["proto"], sock["bindClass"])
                entry = sock_observed.setdefault(key, {})
                entry["samples"] = int(entry.get("samples", 0)) + 1
                entry["lastSeen"] = now
                entry["addresses"] = sorted(
                    set(entry.get("addresses", [])) | {sock["address"]})
                entry["units"] = sorted(
                    set(entry.get("units", []))
                    | ({sock["unit"]} if sock["unit"] else set()))
                entry["users"] = sorted(
                    set(entry.get("users", []))
                    | ({sock["user"]} if sock["user"] else set()))
            # Point-in-time, replaced each run. Negative claims must use the
            # cumulative set above: a listener bound briefly under load would be
            # absent here, and granting unreachability on that basis is exactly the
            # silent wrongness this document exists to avoid.
            doc["sockets"]["current"] = sorted(
                sockets, key=lambda s: (s["port"], s["proto"], s["address"]))

        write_json(STATE, doc)
        write_json(INUSE, project_inuse(doc))

        print(
            "sample %d: %d packages in use, %d observed cumulatively, "
            "%d listening sockets, %d units mapped"
            % (doc["sampleCount"], len(packages), len(observed),
               len(sockets), len(users_map)))


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

    enableSocketObservation = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Also record listening sockets, their bind address, and the user each
        observed unit runs as, exposing them as runtime-facts.json.

        Bind address is the point: a service bound to loopback is unreachable
        from anywhere else whatever the security group says, and neither the Nix
        configuration nor the AWS API can tell you which address a process bound
        to. Requires enableInUseSampler, since it is the same sampler run.
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
      ]
      ++ lib.optional cfg.enableSocketObservation
        "L+ /var/lib/hostinfo/runtime-facts.json - - - - ${inUseDir}/runtime-facts.json";

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
      description = "Sample Nix store paths, listening sockets and unit users";
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
        # ss enumerates sockets via sock_diag over netlink. Denying AF_NETLINK
        # would make it return nothing while still exiting successfully, so the
        # sampler would report no listening sockets on a host full of them.
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
