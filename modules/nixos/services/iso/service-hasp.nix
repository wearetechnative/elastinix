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

  awsCollector = pkgs.writeText "hasp-aws-collector.py" ''
    import json
    import os
    import sys
    import tempfile
    import urllib.error
    import urllib.request
    from datetime import datetime, timezone

    DOC = "${hostinfoDir}/hasp-aws.json"
    MANIFEST = "${registryManifest}"
    TIER = "${cfg.awsFacts}"
    INTERVAL_SECONDS = ${toString cfg.awsFactsIntervalSeconds}
    SCHEMA_VERSION = 1

    IMDS = "http://169.254.169.254"
    TIMEOUT = 3

    # A rule permitting a very wide port range is not usefully expanded into a list
    # of integers. Past this many ports the range is recorded as "all ports open"
    # instead, which is the fact triage actually needs.
    MAX_EXPAND = 256

    WORLD = {"0.0.0.0/0", "::/0"}


    def now_iso():
        return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


    def imds_token():
        req = urllib.request.Request(
            IMDS + "/latest/api/token",
            method="PUT",
            headers={"X-aws-ec2-metadata-token-ttl-seconds": "60"},
        )
        with urllib.request.urlopen(req, timeout=TIMEOUT) as resp:
            return resp.read().decode()


    def imds(token, path, allow_missing=False):
        req = urllib.request.Request(
            IMDS + path, headers={"X-aws-ec2-metadata-token": token}
        )
        try:
            with urllib.request.urlopen(req, timeout=TIMEOUT) as resp:
                return resp.read().decode().strip()
        except urllib.error.HTTPError as exc:
            if exc.code == 404 and allow_missing:
                return None
            raise


    def collect_metadata():
        """The tier that needs no credentials at all."""
        token = imds_token()
        mac = imds(token, "/latest/meta-data/mac")
        base = "/latest/meta-data/network/interfaces/macs/%s" % mac
        groups = imds(token, base + "/security-group-ids") or ""
        public = imds(token, "/latest/meta-data/public-ipv4", allow_missing=True)
        facts = {
            "network.securityGroupIds": sorted(
                g for g in groups.split("\n") if g
            ),
            "network.subnetId": imds(token, base + "/subnet-id"),
            "network.publicIpAttached": bool(public),
        }
        context = {
            "instanceId": imds(token, "/latest/meta-data/instance-id"),
            "vpcId": imds(token, base + "/vpc-id"),
            "region": imds(token, "/latest/meta-data/placement/region"),
        }
        return facts, context


    def expand_ports(rule):
        lo = rule.get("FromPort")
        hi = rule.get("ToPort")
        if rule.get("IpProtocol") == "-1" or lo is None or hi is None:
            return None, True
        if hi - lo + 1 > MAX_EXPAND:
            return list(range(lo, lo + MAX_EXPAND)), True
        return list(range(lo, hi + 1)), False


    def rule_source(rule):
        if rule.get("CidrIpv4"):
            return rule["CidrIpv4"]
        if rule.get("CidrIpv6"):
            return rule["CidrIpv6"]
        ref = rule.get("ReferencedGroupInfo") or {}
        if ref.get("GroupId"):
            return ref["GroupId"]
        if rule.get("PrefixListId"):
            return rule["PrefixListId"]
        return "unknown"


    def collect_api(context, facts):
        """The tier that requires account-wide describe permissions."""
        import boto3

        ec2 = boto3.client("ec2", region_name=context["region"])
        elbv2 = boto3.client("elbv2", region_name=context["region"])

        group_ids = facts["network.securityGroupIds"]
        rules = []
        paginator = ec2.get_paginator("describe_security_group_rules")
        for page in paginator.paginate(
            Filters=[{"Name": "group-id", "Values": group_ids}]
        ):
            rules.extend(page["SecurityGroupRules"])

        ingress = []
        internet_ports = set()
        all_ports_open = False
        from_groups = {}
        egress_unrestricted = False

        for rule in rules:
            source = rule_source(rule)
            ports, wide = expand_ports(rule)
            if rule.get("IsEgress"):
                if source in WORLD and (wide or ports):
                    egress_unrestricted = True
                continue
            ingress.append(
                {
                    "protocol": rule.get("IpProtocol"),
                    "fromPort": rule.get("FromPort"),
                    "toPort": rule.get("ToPort"),
                    "source": source,
                }
            )
            if source in WORLD:
                all_ports_open = all_ports_open or wide
                internet_ports.update(ports or [])
            elif source.startswith("sg-"):
                from_groups.setdefault(source, set()).update(ports or [])
                if wide:
                    all_ports_open = all_ports_open or False

        facts["network.ingressRules"] = sorted(
            ingress, key=lambda r: json.dumps(r, sort_keys=True)
        )
        facts["network.internetReachablePorts"] = sorted(internet_ports)
        facts["network.internetAllPortsOpen"] = all_ports_open
        facts["network.reachableFromGroups"] = sorted(
            (
                {"group": group, "ports": sorted(ports)}
                for group, ports in from_groups.items()
            ),
            key=lambda entry: entry["group"],
        )
        facts["network.egressUnrestricted"] = egress_unrestricted
        facts["network.subnetTier"] = subnet_tier(ec2, context, facts)
        facts["network.behindLoadBalancer"] = behind_load_balancer(
            elbv2, context["instanceId"]
        )
        facts["data.persistentVolumes"] = sorted(
            volume["VolumeId"]
            for volume in ec2.describe_volumes(
                Filters=[
                    {
                        "Name": "attachment.instance-id",
                        "Values": [context["instanceId"]],
                    }
                ]
            )["Volumes"]
        )
        return facts


    def subnet_tier(ec2, context, facts):
        subnet_id = facts["network.subnetId"]
        tables = ec2.describe_route_tables(
            Filters=[{"Name": "association.subnet-id", "Values": [subnet_id]}]
        )["RouteTables"]
        if not tables:
            # A subnet with no explicit association uses the VPC main route table.
            # Filtering only on the subnet would return nothing here and read a
            # public subnet as private.
            tables = ec2.describe_route_tables(
                Filters=[
                    {"Name": "vpc-id", "Values": [context["vpcId"]]},
                    {"Name": "association.main", "Values": ["true"]},
                ]
            )["RouteTables"]
        default_routes = [
            route
            for table in tables
            for route in table.get("Routes", [])
            if route.get("DestinationCidrBlock") == "0.0.0.0/0"
        ]
        if any(
            (route.get("GatewayId") or "").startswith("igw-")
            for route in default_routes
        ):
            return "public"
        if default_routes:
            return "private"
        return "isolated"


    def behind_load_balancer(elbv2, instance_id):
        paginator = elbv2.get_paginator("describe_target_groups")
        for page in paginator.paginate():
            for group in page["TargetGroups"]:
                health = elbv2.describe_target_health(
                    TargetGroupArn=group["TargetGroupArn"]
                )
                for target in health["TargetHealthDescriptions"]:
                    if target["Target"]["Id"] == instance_id:
                        return True
        return False


    def validate(facts):
        """Rule 3 at runtime: the registry still governs which keys may exist."""
        with open(MANIFEST) as fh:
            registry = json.load(fh)
        problems = []
        for key, value in facts.items():
            entry = registry.get(key)
            if entry is None:
                problems.append("%s: absent from registry" % key)
                continue
            expected = entry["type"]
            actual = (
                "bool" if isinstance(value, bool)
                else "int" if isinstance(value, int)
                else "string" if isinstance(value, str)
                else "list" if isinstance(value, list)
                else "attrs" if isinstance(value, dict)
                else "unknown"
            )
            if actual != expected:
                problems.append(
                    "%s: type %s, registry says %s" % (key, actual, expected)
                )
            if isinstance(value, list):
                encoded = [json.dumps(v, sort_keys=True) for v in value]
                if encoded != sorted(encoded):
                    problems.append("%s: list is not sorted" % key)
        return problems


    def load_previous():
        try:
            with open(DOC) as fh:
                return json.load(fh)
        except (OSError, ValueError):
            return None


    def write_doc(payload):
        fd, tmp = tempfile.mkstemp(dir=os.path.dirname(DOC), suffix=".tmp")
        try:
            with os.fdopen(fd, "w") as fh:
                json.dump(payload, fh, indent=1, sort_keys=True)
            # mkstemp creates 0600 and os.replace preserves it, which would leave
            # the document unreadable by the hostinfo HTTP server (it runs as
            # nobody) and serve a 404 despite the file existing.
            os.chmod(tmp, 0o644)
            os.replace(tmp, DOC)
        except BaseException:
            os.unlink(tmp)
            raise


    def main():
        stamp = now_iso()
        previous = load_previous()

        try:
            facts, context = collect_metadata()
            if TIER == "api":
                facts = collect_api(context, facts)
        except Exception as exc:
            # Never write a partial document. A stale document that a consumer can
            # detect is strictly better than a fresh one that quietly lost half its
            # facts, because absence of a fact reads as absence of risk.
            print("collection failed, keeping previous document: %r" % (exc,),
                  file=sys.stderr)
            return 3

        problems = validate(facts)
        if problems:
            print("collected facts rejected by the registry:", file=sys.stderr)
            for problem in problems:
                print("  " + problem, file=sys.stderr)
            return 4

        prev_facts = (previous or {}).get("facts", {})
        prev_values = {k: v["value"] for k, v in prev_facts.items()}
        changed = sorted(
            key for key in set(prev_values) | set(facts)
            if prev_values.get(key) != facts.get(key)
        )

        last_changed = {
            key: entry.get("lastChanged", stamp)
            for key, entry in prev_facts.items()
        }
        for key in changed:
            last_changed[key] = stamp

        doc = {
            "schemaVersion": SCHEMA_VERSION,
            "tier": TIER,
            "intervalSeconds": INTERVAL_SECONDS,
            "instanceId": context["instanceId"],
            "region": context["region"],
            "firstCollected": (previous or {}).get("firstCollected", stamp),
            "lastCollected": stamp,
            "collectionCount": int((previous or {}).get("collectionCount", 0)) + 1,
            "changedKeys": changed if previous else [],
            "facts": {
                key: {
                    "value": value,
                    "source": "aws",
                    "evidence": "%s tier, %s" % (TIER, context["instanceId"]),
                    "lastChanged": last_changed.get(key, stamp),
                }
                for key, value in facts.items()
            },
        }

        write_doc(doc)

        if previous and changed:
            # The exposure of this machine changed without a rebuild. That is the
            # event the whole drift question is about, so it goes to the journal
            # where it can be alerted on.
            print("ATTACK SURFACE CHANGED: " + ", ".join(changed), file=sys.stderr)
            for key in changed:
                print(
                    "  %s: %r -> %r"
                    % (key, prev_values.get(key), facts.get(key)),
                    file=sys.stderr,
                )
            return 1

        print(
            "collected %d AWS facts (%s tier, collection %d)"
            % (len(facts), TIER, doc["collectionCount"])
        )
        return 0


    if __name__ == "__main__":
        sys.exit(main())
  '';

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
      scores. See docs/hasp-framework.md
    '';

    declared = {
      environment = lib.mkOption {
        type = lib.types.enum [ "prod" "nonprod" "dev" ];
        description = ''
          Deployment environment. No default: a substituted value would be a
          claim made by nobody that is nonetheless cited in an audit.
        '';
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
        description = ''
          Classification of data this host handles. Bears on the risk threshold
          rather than on exploitability. No default, deliberately.
        '';
      };

      isJumphost = lib.mkOption {
        type = lib.types.bool;
        description = ''
          Whether this host is a jumphost. Intent rather than configuration — a
          jumphost is one because we say so — so it is declared, not derived.
        '';
      };

      reviewedBy = lib.mkOption {
        type = lib.types.str;
        description = "Who last reviewed this declared block.";
      };

      reviewedAt = lib.mkOption {
        type = lib.types.str;
        example = "2026-08-27";
        description = ''
          Date this declared block was last reviewed, ISO 8601.

          Staleness is not checked at build time because Nix has no clock by
          design; the value is published and alerted on from Prometheus.
        '';
      };
    };

    awsFacts = lib.mkOption {
      type = lib.types.enum [ "none" "metadata" "api" ];
      default = "none";
      description = ''
        Collect infrastructure facts on this machine, on a timer, publishing
        them as hasp-aws.json.

        Deliberately not part of hasp.json: these facts change without a
        rebuild, so hashing them would either freeze a stale value or rehash on
        every collection. They are queried from the live AWS API rather than
        from Terraform state, which records what Terraform last believed.

        - "none"     no collection.
        - "metadata" security group ids, subnet and public-IP presence, read
                     from the instance metadata service. Requires **no IAM
                     whatsoever** and adds nothing to the closure.
        - "api"      the above plus ingress rules, which other security groups
                     can reach this host, subnet tier, load balancer
                     attachment and attached volumes.

        The "api" tier requires account-wide `ec2:Describe*` on the instance
        profile. EC2 describe actions do not support resource-level
        permissions, so they cannot be scoped to the resources this host owns:
        granting them means every host can enumerate every security group,
        subnet and route table in the account. Choose it deliberately.
      '';
    };

    awsFactsIntervalSeconds = lib.mkOption {
      type = lib.types.ints.positive;
      default = 900;
      description = ''
        Seconds between collections. Also written into the document so
        consumers can tell a stale document from a fresh one.
      '';
    };

    documentFile = lib.mkOption {
      type = lib.types.path;
      internal = true;
      readOnly = true;
      description = ''
        The generated profile as a store path. Exposed so consumers — the drift
        self-check, tests — can reference the closure artifact directly rather
        than depending on tmpfiles having run.
      '';
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
          ExecStart = "${collectorPython}/bin/python3 ${awsCollector}";
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
