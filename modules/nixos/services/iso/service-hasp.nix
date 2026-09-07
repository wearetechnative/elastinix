{ config, lib, pkgs, ... }:

let
  cfg = config.elastinix.hasp;

  schemaVersion = 2;
  registryVersion = 2;

  hostRegistry = {
    "identity.hostname" = { type = "string"; source = "derived"; };
    "identity.environment" = { type = "string"; source = "declared"; };
    "identity.role" = { type = "string"; source = "declared"; };
    "identity.owner" = { type = "string"; source = "declared"; };
    "identity.dataClassification" = { type = "string"; source = "declared"; };

    "network.securityGroupIds" = { type = "list"; source = "aws"; tier = "metadata"; };
    "network.subnetId" = { type = "string"; source = "aws"; tier = "metadata"; };
    "network.publicIpAttached" = { type = "bool"; source = "aws"; tier = "metadata"; };

    "network.subnetTier" = { type = "string"; source = "aws"; tier = "api"; };
    "network.ingressRules" = { type = "list"; source = "aws"; tier = "api"; };
    "network.internetReachablePorts" = { type = "list"; source = "aws"; tier = "api"; };
    "network.internetAllPortsOpen" = { type = "bool"; source = "aws"; tier = "api"; };
    "network.reachableFromGroups" = { type = "list"; source = "aws"; tier = "api"; };
    "network.behindLoadBalancer" = { type = "bool"; source = "aws"; tier = "api"; };
    "network.egressUnrestricted" = { type = "bool"; source = "aws"; tier = "api"; };

    "network.firewallEnabled" = { type = "bool"; source = "derived"; };
    "network.firewallOpenTcpPorts" = { type = "list"; source = "derived"; };
    "network.firewallOpenUdpPorts" = { type = "list"; source = "derived"; };
    "network.isJumphost" = { type = "bool"; source = "declared"; };

    "runtime.dockerEnabled" = { type = "bool"; source = "derived"; };
    "runtime.localDatabases" = { type = "list"; source = "derived"; };
    "runtime.nixosStateVersion" = { type = "string"; source = "derived"; };

    "data.persistentVolumes" = { type = "list"; source = "aws"; tier = "api"; };
  };

  fleetRegistry = {
    "fleet.systemdHardeningDefault" = { type = "bool"; source = "derived"; };
    "fleet.fail2banEnabled" = { type = "bool"; source = "derived"; };
    "fleet.auditdEnabled" = { type = "bool"; source = "derived"; };
    "fleet.centralLogShipping" = { type = "bool"; source = "derived"; };
    "fleet.sshPasswordAuthentication" = { type = "bool"; source = "derived"; };
    "fleet.inUseSamplerEnabled" = { type = "bool"; source = "derived"; };
  };

  # The AWS document is written straight into the directory hostinfo serves, so
  # it needs no symlink. hasp.json cannot follow: it is a build product living in
  # the Nix store, with no runtime state to place anywhere.
  hostinfoDir = "/var/lib/hostinfo";

  registryManifest = pkgs.writeText "hasp-registry.json"
    (builtins.toJSON (hostRegistry // fleetRegistry));

  # ── Helpers ───────────────────────────────────────────────────────────────

  mkFact = source: evidence: value: { inherit value source evidence; };

  factLessThan = a: b:
    if builtins.isInt a && builtins.isInt b
    then a < b
    else builtins.toJSON a < builtins.toJSON b;

  isSorted = l: l == lib.sort factLessThan l;

  typeOfValue = v:
    if builtins.isBool v then "bool"
    else if builtins.isInt v then "int"
    else if builtins.isString v then "string"
    else if builtins.isList v then "list"
    else if builtins.isAttrs v then "attrs"
    else "unknown";

  # ── Derived facts ─────────────────────────────────────────────────────────

  firewallEnabled = config.networking.firewall.enable or false;

  openPorts = attr:
    lib.optionals firewallEnabled
      (lib.sort factLessThan (lib.unique (config.networking.firewall.${attr} or [ ])));

  databaseProbes = {
    postgresql = config.services.postgresql.enable or false;
    mysql = config.services.mysql.enable or false;
    mongodb = config.services.mongodb.enable or false;
    redis = (config.services.redis.servers or { }) != { };
  };

  databaseEngines = lib.attrNames databaseProbes;

  localDatabases = lib.sort factLessThan
    (lib.attrNames (lib.filterAttrs (_: v: v) databaseProbes));

  logShippingEnabled =
    (config.services.alloy.enable or false)
    || (config.services.vector.enable or false)
    || (config.services.fluent-bit.enable or false);

  sshPasswordAuth =
    let v = (config.services.openssh.settings or { }).PasswordAuthentication or null;
    in if v == null then true else v;

  derivedHostFacts = {
    "identity.hostname" =
      mkFact "derived" "config.networking.hostName" config.networking.hostName;
    "network.firewallEnabled" =
      mkFact "derived" "config.networking.firewall.enable" firewallEnabled;
    "network.firewallOpenTcpPorts" =
      mkFact "derived"
        (if firewallEnabled
         then "config.networking.firewall.allowedTCPPorts"
         else "firewall disabled, every TCP port reachable")
        (openPorts "allowedTCPPorts");
    "network.firewallOpenUdpPorts" =
      mkFact "derived"
        (if firewallEnabled
         then "config.networking.firewall.allowedUDPPorts"
         else "firewall disabled, every UDP port reachable")
        (openPorts "allowedUDPPorts");
    "runtime.dockerEnabled" =
      mkFact "derived" "config.virtualisation.docker.enable"
        (config.virtualisation.docker.enable or false);
    "runtime.localDatabases" =
      mkFact "derived"
        "config.services.{${lib.concatStringsSep "," databaseEngines}}.enable (partial list)"
        localDatabases;
    "runtime.nixosStateVersion" =
      mkFact "derived" "config.system.stateVersion" config.system.stateVersion;
  };

  declaredEvidence = "${cfg.declared.reviewedBy}, ${cfg.declared.reviewedAt}";

  declaredHostFacts = {
    "identity.environment" =
      mkFact "declared" declaredEvidence cfg.declared.environment;
    "identity.role" = mkFact "declared" declaredEvidence cfg.declared.role;
    "identity.owner" = mkFact "declared" declaredEvidence cfg.declared.owner;
    "identity.dataClassification" =
      mkFact "declared" declaredEvidence cfg.declared.dataClassification;
    "network.isJumphost" =
      mkFact "declared" declaredEvidence cfg.declared.isJumphost;
  };

  fleetFacts = {
    "fleet.systemdHardeningDefault" =
      mkFact "derived" "elastinix service modules apply hardening by default" true;
    "fleet.fail2banEnabled" =
      mkFact "derived" "modules/nixos/services/base-system.nix"
        (config.services.fail2ban.enable or false);
    "fleet.auditdEnabled" =
      mkFact "derived" "config.security.auditd.enable"
        (config.security.auditd.enable or false);
    "fleet.centralLogShipping" =
      mkFact "derived" "config.services.{alloy,vector,fluent-bit}.enable"
        logShippingEnabled;
    "fleet.sshPasswordAuthentication" =
      mkFact "derived" "config.services.openssh.settings.PasswordAuthentication"
        sshPasswordAuth;
    "fleet.inUseSamplerEnabled" =
      mkFact "derived" "config.elastinix.services.hostinfo.enableInUseSampler"
        (config.elastinix.services.hostinfo.enableInUseSampler or false);
  };

  # ── AWS facts ─────────────────────────────────────────────────────────────

  # ── Assembly ──────────────────────────────────────────────────────────────

  hostFacts = derivedHostFacts // declaredHostFacts;

  valuesOf = facts: lib.mapAttrs (_: f: f.value) facts;

  hashOf = facts:
    builtins.substring 0 16
      (builtins.hashString "sha256" (builtins.toJSON (valuesOf facts)));

  document = {
    inherit schemaVersion registryVersion;
    host = config.networking.hostName;
    haspHash = hashOf hostFacts;
    fleetHash = hashOf fleetFacts;
    declaredReview = {
      by = cfg.declared.reviewedBy;
      at = cfg.declared.reviewedAt;
    };
    facts = hostFacts;
    fleet = fleetFacts;
  };

  haspJson = pkgs.writeText "hasp.json" (builtins.toJSON document);

  collectorPython =
    if cfg.awsFacts == "api"
    then pkgs.python3.withPackages (ps: [ ps.boto3 ])
    else pkgs.python3;

  awsCollector = pkgs.writeText "hasp-aws-collector.py"
    (builtins.readFile ./hasp-aws-collector.py);

  # ── Validation ────────────────────────────────────────────────────────────

  registered = registry: facts: lib.filterAttrs (k: _: registry ? ${k}) facts;

  unregisteredIn = registry: facts:
    lib.subtractLists (lib.attrNames registry) (lib.attrNames facts);

  wrongSourceIn = registry: facts: lib.attrNames (lib.filterAttrs
    (k: f: (registry.${k}.source or null) != f.source)
    (registered registry facts));

  wrongTypeIn = registry: facts: lib.attrNames (lib.filterAttrs
    (k: f: typeOfValue f.value != registry.${k}.type)
    (registered registry facts));

  unsortedIn = facts: lib.attrNames (lib.filterAttrs
    (_: f: builtins.isList f.value && !(isSorted f.value))
    facts);

  unregisteredKeys =
    unregisteredIn hostRegistry hostFacts
    ++ unregisteredIn fleetRegistry fleetFacts;

  wrongSource =
    wrongSourceIn hostRegistry hostFacts
    ++ wrongSourceIn fleetRegistry fleetFacts;

  wrongType =
    wrongTypeIn hostRegistry hostFacts
    ++ wrongTypeIn fleetRegistry fleetFacts;

  unsortedLists = unsortedIn hostFacts ++ unsortedIn fleetFacts;

in
{
  options.elastinix.hasp = {
    enable = lib.mkEnableOption ''
      Host Attack Surface Profile: a static, content-hashed per-host fact
      document served by hostinfo, describing how the machine is exposed.

      It answers one question — given that a package is vulnerable, what about
      this machine makes that matter — and contains no CVEs, no verdicts and no
      scores. See docs/services/hasp.md
    '';

    declared = {
      environment = lib.mkOption {
        type = lib.types.enum [ "prod" "nonprod" "dev" ];
        description = "Deployment environment. Declared with no default: a substituted value would be a claim nobody made.";
      };

      role = lib.mkOption {
        type = lib.types.str;
        description = "What this machine is for, in a few words.";
      };

      owner = lib.mkOption {
        type = lib.types.str;
        description = "Team accountable for remediating findings on this host.";
      };

      dataClassification = lib.mkOption {
        type = lib.types.enum [ "public" "internal" "confidential" "special" ];
        description = "Classification of data this host handles. Bears on the risk threshold, not on exploitability.";
      };

      isJumphost = lib.mkOption {
        type = lib.types.bool;
        description = "Whether this host is a jumphost. Declared intent rather than derived configuration.";
      };

      reviewedBy = lib.mkOption {
        type = lib.types.str;
        description = "Who last reviewed this declared block.";
      };

      reviewedAt = lib.mkOption {
        type = lib.types.str;
        example = "2026-08-27";
        description = "Date the declared block was last reviewed, ISO 8601. Staleness is alerted on from Prometheus, not at build time.";
      };
    };

    awsFacts = lib.mkOption {
      type = lib.types.enum [ "none" "metadata" "api" ];
      default = "none";
      description = "Collect infrastructure facts on a timer as hasp-aws.json: `metadata` needs no IAM, `api` adds ingress and reachability but requires account-wide ec2:Describe*. See docs/services/hasp.md.";
    };

    awsFactsIntervalSeconds = lib.mkOption {
      type = lib.types.ints.positive;
      default = 900;
      description = "Seconds between collections; also written into the document so consumers can spot a stale one.";
    };

    documentFile = lib.mkOption {
      type = lib.types.path;
      internal = true;
      readOnly = true;
      description = "The generated profile as a store path, for consumers that must not depend on tmpfiles having run.";
    };

  };

  config = lib.mkIf cfg.enable {

    assertions = [
      {
        assertion = config.elastinix.services.hostinfo.enable;
        message = ''
          elastinix.hasp requires elastinix.services.hostinfo.enable: the
          profile is served from /var/lib/hostinfo over the hostinfo port.
        '';
      }
      {
        assertion = unregisteredKeys == [ ];
        message = ''
          elastinix.hasp: fact keys absent from registry v${toString registryVersion}:
            ${lib.concatStringsSep ", " unregisteredKeys}
          Verdicts reference facts by key, so an unregistered key would produce
          a verdict that silently never invalidates. Fix the key or extend the
          registry in modules/nixos/services/service-hasp.nix.
        '';
      }
      {
        assertion = wrongSource == [ ];
        message = ''
          elastinix.hasp: facts whose source disagrees with the registry:
            ${lib.concatStringsSep ", " wrongSource}
        '';
      }
      {
        assertion = wrongType == [ ];
        message = ''
          elastinix.hasp: facts whose value type disagrees with the registry:
            ${lib.concatStringsSep ", " wrongType}
        '';
      }
      {
        assertion = unsortedLists == [ ];
        message = ''
          elastinix.hasp: list facts that are not sorted:
            ${lib.concatStringsSep ", " unsortedLists}
          Unsorted lists rehash whenever upstream ordering shifts, invalidating
          verdicts for no reason.
        '';
      }
    ];

    elastinix.hasp.documentFile = haspJson;

    systemd.tmpfiles.rules = [
      "L+ ${hostinfoDir}/hasp.json - - - - ${haspJson}"
    ];

    systemd.services.elastinix-hasp-aws-collector =
      lib.mkIf (cfg.awsFacts != "none") {
        description = "Collect AWS infrastructure facts for the HASP profile";
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];

        serviceConfig = {
          Type = "oneshot";
          # Root because the state directory must be traversable by the
          # unprivileged hostinfo HTTP server, which rules out DynamicUser --
          # its state lives under /var/lib/private, mode 0700.
          User = "root";
          Group = "root";
          ExecStart = lib.concatStringsSep " " [
            "${collectorPython}/bin/python3"
            "${awsCollector}"
            "--doc ${hostinfoDir}/hasp-aws.json"
            "--manifest ${registryManifest}"
            "--tier ${cfg.awsFacts}"
            "--interval-seconds ${toString cfg.awsFactsIntervalSeconds}"
          ];
          ReadWritePaths = [ hostinfoDir ];

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
          ProtectProc = "invisible";

          RestrictAddressFamilies = [ "AF_INET" "AF_INET6" "AF_NETLINK" ];
        } // lib.optionalAttrs (cfg.awsFacts == "metadata") {
          IPAddressDeny = "any";
          IPAddressAllow = "169.254.169.254/32";
        };
      };

    systemd.timers.elastinix-hasp-aws-collector =
      lib.mkIf (cfg.awsFacts != "none") {
        description = "Timer for HASP AWS fact collection";
        wantedBy = [ "timers.target" ];

        timerConfig = {
          OnBootSec = "3min";
          OnUnitActiveSec = "${toString cfg.awsFactsIntervalSeconds}s";
          AccuracySec = "30s";
        };
      };
  };
}
