import argparse
import json
import os
import sys
import tempfile
import urllib.error
import urllib.request
from datetime import datetime, timezone

DOC = None
MANIFEST = None
TIER = None
INTERVAL_SECONDS = None
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
    global DOC, MANIFEST, TIER, INTERVAL_SECONDS

    parser = argparse.ArgumentParser()
    parser.add_argument("--doc", required=True)
    parser.add_argument("--manifest", required=True)
    parser.add_argument("--tier", required=True, choices=["metadata", "api"])
    parser.add_argument("--interval-seconds", type=int, required=True)
    args = parser.parse_args()

    DOC = args.doc
    MANIFEST = args.manifest
    TIER = args.tier
    INTERVAL_SECONDS = args.interval_seconds

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
