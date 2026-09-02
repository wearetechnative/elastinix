# HASP Service

The HASP service (`elastinix.hasp`) publishes a **Host Attack Surface Profile**: a
static, content-hashed document describing how the machine is exposed, served by
[hostinfo](hostinfo.md) as `hasp.json`.

It answers one question, and only this question:

> Given that this package is vulnerable, what about *this machine* makes that
> matter, or not matter?

It contains no CVEs, no verdicts, no scores and no prose. For the framework it
belongs to, see [HASP Framework](../hasp-framework.md); for the programme it
serves, [Vulnix CVE Automation](../vulnix-cve-automation.md).

## Features

- **Static and pure**: evaluated at build time into a single store path. No
  generator service, no timer, nothing to fail at three in the morning
- **Content-hashed**: `haspHash` covers fact *values* only, so correcting an
  evidence string or re-confirming a review never invalidates a triage verdict
- **Closed fact registry**: an unregistered key, a wrong declared source or a
  wrong value type fails the build — checked for the `fleet` section too, since a
  section validated by nothing is where a mistake goes unnoticed
- **No defaults for judgement**: a missing declared fact fails the build
- **Credential-free infrastructure facts**: an optional on-host collector reads
  the instance metadata service, needing no AWS permissions at all, and reports
  when the machine's exposure changes

## Configuration

### Minimal

```nix
elastinix.services.hostinfo.enable = true;

elastinix.hasp = {
  enable = true;
  declared = {
    environment        = "prod";
    role               = "customer-facing application host";
    owner              = "managed-services";
    dataClassification = "confidential";
    isJumphost         = false;
    reviewedBy         = "luca.kasper";
    reviewedAt         = "2026-08-27";
  };
};
```

### With infrastructure facts

```nix
elastinix.hasp = {
  enable = true;
  declared = { /* as above */ };

  awsFacts = "metadata";   # no IAM at all; or "api" for the full set
};
```

## Configuration Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `enable` | boolean | `false` | Publish the profile |
| `declared.environment` | enum | *none* | `prod`, `nonprod`, `dev` |
| `declared.role` | string | *none* | What the machine is for |
| `declared.owner` | string | *none* | Team accountable for remediation |
| `declared.dataClassification` | enum | *none* | `public`, `internal`, `confidential`, `special` |
| `declared.isJumphost` | boolean | *none* | Intent, not configuration |
| `declared.reviewedBy` | string | *none* | Who last reviewed the declared block |
| `declared.reviewedAt` | string | *none* | Review date, ISO 8601 |
| `awsFacts` | enum | `"none"` | `none`, `metadata` or `api` — see below |
| `awsFactsIntervalSeconds` | positive int | `900` | Seconds between collections |

**None of the declared options has a default, deliberately.** A
`dataClassification` that defaults to `internal` is not a missing value — it is a
false claim, made by nobody, that will be cited in an audit. A missing
declaration fails the build.

### `awsFacts` tiers, and what each one costs

| Tier | Facts | IAM required | Closure |
|---|---|---|---|
| `none` | — | — | — |
| `metadata` | `securityGroupIds`, `subnetId`, `publicIpAttached` | **none** | unchanged |
| `api` | the above plus `ingressRules`, `internetReachablePorts`, `internetAllPortsOpen`, `reachableFromGroups`, `subnetTier`, `behindLoadBalancer`, `egressUnrestricted`, `persistentVolumes` | account-wide `ec2:Describe*` | +~120 MB |

**The `metadata` tier is free.** The instance metadata service needs no
credentials, so a host with an empty instance profile still publishes its
attached security group set, its subnet, and whether a public IP is present —
which are the two highest-consequence exposures plus the identity to correlate
them.

**The `api` tier's cost is not scopable.** EC2 describe actions do not support
resource-level permissions, so `ec2:DescribeSecurityGroupRules` cannot be limited
to the groups this host is in. Granting it means the host can enumerate every
security group, subnet and route table in the account. Read-only, but
account-wide. Choose it per host, for the detail it buys:

```
ec2:DescribeSecurityGroupRules   ec2:DescribeRouteTables
ec2:DescribeVolumes              elasticloadbalancing:DescribeTargetGroups
                                 elasticloadbalancing:DescribeTargetHealth
```

What the `api` tier uniquely adds is `reachableFromGroups`. Knowing a host is
reachable *from the jumphost* rather than merely "not from the internet" is the
fact most likely to change a verdict, and the metadata tier cannot see it.

## Fact registry

Every fact carries `value`, `source` and `evidence`. `evidence` is what makes a
triage record answerable: *"not reachable from the internet"* invites an argument,
*"`sg-0f3a1c9d` permits 443 from `sg-jumphost` only"* ends one.

### Host facts

| Key | Source | Notes |
|---|---|---|
| `identity.hostname` | derived | |
| `identity.environment` | declared | |
| `identity.role` | declared | |
| `identity.owner` | declared | |
| `identity.dataClassification` | declared | Bears on the risk threshold, not exploitability |
| `network.securityGroupIds` | aws · metadata | Change reported by the collector |
| `network.subnetId` | aws · metadata | |
| `network.publicIpAttached` | aws · metadata | Change reported by the collector |
| `network.subnetTier` | aws · api | `public`, `private`, `isolated` |
| `network.ingressRules` | aws · api | One entry per permitted rule — raw evidence |
| `network.internetReachablePorts` | aws · api | Ports whose source resolves to `0.0.0.0/0` |
| `network.internetAllPortsOpen` | aws · api | Set when a world-facing rule covers all protocols or a very wide range |
| `network.reachableFromGroups` | aws · api | `{ group, ports }` per referencing group |
| `network.behindLoadBalancer` | aws · api | |
| `network.egressUnrestricted` | aws · api | |
| `network.firewallOpenPorts` | derived | Host firewall, TCP and UDP merged |
| `network.isJumphost` | declared | |
| `runtime.dockerEnabled` | derived | |
| `runtime.localDatabases` | derived | Partial list — see below |
| `runtime.nixosStateVersion` | derived | |
| `data.persistentVolumes` | aws · api | |

`network.reachableFromGroups` matters more than it looks. A host with
`internetReachablePorts: []` reads as unreachable, when it may be reachable from
a jumphost by every engineer in the company. For a CVE needing only
adjacent-network access, the two are entirely different situations.

`firewallOpenPorts` and `internetReachablePorts` deliberately overlap: a port open
in the host firewall but closed at the security group is a different risk from one
open in both.

**`aws`-sourced facts are not in `hasp.json`.** They live in `hasp-aws.json`
because they change without a rebuild — hashing them into the profile would either
freeze a stale value or rehash on every collection. Verdicts are unaffected: they
remember fact *values* and compare against whichever document carries the key.

`data.backupsConfigured` was drafted and dropped. Nothing we run can produce it,
and a registered fact no collector fills is decoration.

### Fleet facts

Facts with no variance across hosts, carried in a `fleet` section with its own
`fleetHash`. They cannot discriminate between findings, so presenting them as
per-host facts would overstate what they tell us — but a fleet-wide regression
must still invalidate verdicts that leaned on them.

| Key | Notes |
|---|---|
| `fleet.systemdHardeningDefault` | Elastinix services hardened by default |
| `fleet.fail2banEnabled` | Unconditional in `base-system.nix` |
| `fleet.auditdEnabled` | Currently `false` fleet-wide |
| `fleet.centralLogShipping` | Currently `false` — is there anywhere to look after an incident |
| `fleet.sshPasswordAuthentication` | nixpkgs default |
| `fleet.inUseSamplerEnabled` | Whether runtime evidence exists for this host at all |

That three of these are `false` makes the group read as a to-do list rather than
as evidence of controls. Publishing it is the point.

### Why some facts are not here

**No package names or versions**, and no enumeration of an upstream-defined set.
Every deploy changes the closure; if closure contents were part of the profile the
hash would change on every deploy and every verdict would invalidate
continuously.

This bites less obviously than it sounds. A "units running as root" fact would be
about 47 entries on a stock system, almost all nixpkgs-owned, and a nixpkgs bump
would churn it. Facts about what actually runs are therefore *observed* instead —
see `enableSocketObservation` in [hostinfo](hostinfo.md).

**`runtime.localDatabases` is a partial list** and its evidence string says so.
Each engine has to be named individually because renamed and removed upstream
options *abort evaluation when accessed* — reading
`config.services.redis.enable` throws `Renaming error`, which `or` does not
catch — so a generic probe across the upstream namespace is unsafe.

## Output

`/var/lib/hostinfo/hasp.json`, a symlink into the store — the one document here
that cannot be written where it is served, because it is a pure build product
with no runtime state to place:

```json
{
  "schemaVersion": 2,
  "registryVersion": 1,
  "host": "compute5-prod",
  "haspHash": "41bc73f50fc569ce",
  "fleetHash": "960e9e1e56f71034",
  "declaredReview": { "by": "luca.kasper", "at": "2026-08-27" },
  "facts": {
    "network.firewallOpenPorts": {
      "value": [22, 3333],
      "source": "derived",
      "evidence": "config.networking.firewall.allowed{TCP,UDP}Ports"
    }
  },
  "fleet": { }
}
```

There is deliberately no generation timestamp. A pure store path has no build
clock, and a fabricated one would be the only untrustworthy field in the
document. Consumers record their own fetch time instead.

### `hasp-aws.json`

Written on the machine by `elastinix-hasp-aws-collector.service`, on a timer, from
the **live AWS API** — not from Terraform state, which records what Terraform last
believed rather than what is.

Written straight to `/var/lib/hostinfo/hasp-aws.json`, the directory hostinfo
serves, so no symlink is involved. The collector therefore holds
`ReadWritePaths=/var/lib/hostinfo`: it renames a temporary file into place, which
needs write access to the containing directory. A truncating write would let the
scanner fetch a half-written document and read a missing fact as an absent risk.

```json
{
  "schemaVersion": 1,
  "tier": "metadata",
  "intervalSeconds": 900,
  "instanceId": "i-0123456789abcdef0",
  "region": "eu-central-1",
  "firstCollected": "2026-08-27T09:24:36Z",
  "lastCollected": "2026-08-27T09:39:36Z",
  "collectionCount": 3,
  "changedKeys": ["network.publicIpAttached", "network.securityGroupIds"],
  "facts": {
    "network.securityGroupIds": {
      "value": ["sg-04bb2e77", "sg-0f3a1c9d"],
      "source": "aws",
      "evidence": "metadata tier, i-0123456789abcdef0",
      "lastChanged": "2026-08-27T09:24:36Z"
    }
  }
}
```

`lastChanged` per fact and `changedKeys` for the latest transition are what make
this a drift record rather than a snapshot.

**The registry still governs it.** The fact registry is emitted into the closure
as `hasp-registry.json`, and the collector validates its own output against it
before writing: an unregistered key, a type that disagrees, or an unsorted list
makes it exit non-zero without writing. Rule 3 is enforced at runtime for facts
produced outside evaluation.

Two implementation traps worth recording, both handled: a subnet with no explicit
route table association uses the VPC **main** route table, and filtering only on
`association.subnet-id` would read a public subnet as private; and a rule
permitting a very wide port range is recorded as `internetAllPortsOpen` rather
than expanded into tens of thousands of integers.

## Change detection

The facts that carry the most triage weight can change with no Nix evaluation at
all: a console edit, a targeted `terraform apply`, another team's module. Because
the collector re-reads reality every interval, it *is* the drift detection — there
is no separate check.

Each collection is compared against the previously published document. When
anything differs, the collector names the changed keys with their before and after
values and exits non-zero, so the event is alertable:

```
ATTACK SURFACE CHANGED: network.publicIpAttached, network.securityGroupIds
  network.publicIpAttached: False -> True
  network.securityGroupIds: ['sg-04bb2e77', 'sg-0f3a1c9d'] -> [..., 'sg-NEW']
```

Exit codes:

| Exit | Meaning |
|---|---|
| 0 | Collected; nothing changed |
| 1 | Collected; the machine's exposure changed |
| 3 | Collection failed — previous document kept, nothing written |
| 4 | Collected facts rejected by the registry — nothing written |

**A failed collection never publishes a partial document.** On any error the
previous document is kept and the unit fails. A stale document is detectable from
`lastCollected`; a fresh one that quietly lost half its facts is not, and an absent
fact reads as an absent risk.

**Unavailability is not agreement.** An unreachable metadata service exits 3
rather than reporting no change, so a host with a broken collector cannot look
verified.

The collector modifies nothing else — not `hasp.json`, not any triage record, and
no AWS resource. Its only outputs are its own document and its report.

## Systemd Units

| Unit | Type | Description |
|------|------|-------------|
| `elastinix-hasp-aws-collector.service` | oneshot | Collects infrastructure facts and reports change |
| `elastinix-hasp-aws-collector.timer` | timer | Every `awsFactsIntervalSeconds` |

No unit generates `hasp.json` — it is a store path.

## Useful Commands

```bash
# Read the profile
curl -s http://localhost:3333/hasp.json | jq .

# Just the hashes
curl -s http://localhost:3333/hasp.json | jq '{haspHash, fleetHash}'

# Facts by provenance
curl -s http://localhost:3333/hasp.json \
  | jq '.facts | to_entries | group_by(.value.source) | map({(.[0].value.source): length}) | add'

# Raw collector evidence
curl -s http://localhost:3333/hasp-aws.json | jq .

# Collect by hand
systemctl start elastinix-hasp-aws-collector.service
journalctl -u elastinix-hasp-aws-collector.service -n 20

# When did each collected fact last change?
curl -s http://localhost:3333/hasp-aws.json \
  | jq '.facts | map_values(.lastChanged)'

# Every exposure change this host has seen
journalctl -u elastinix-hasp-aws-collector.service | grep -A3 "ATTACK SURFACE CHANGED"
```

## Security

The profile is, by construction, a description of the machine's attack surface.
It sits behind the same trust boundary that already carries `services.json` and
`packages.json`, which between them list every enabled service and every installed
package with versions, so it adds context rather than a new class of exposure.

Two conditions attach: it must not be reachable outside the VPC, and if hostinfo
gains external exposure through the planned nginx vhost (bean
`elastinix-n3zn`), authentication is a prerequisite rather than a follow-up.

The collector runs with `ProtectSystem=strict`, `ProtectProc=invisible` and write
access only to its own state directory. On the `metadata` tier it also carries
`IPAddressDeny=any` with `IPAddressAllow=169.254.169.254/32`, so it can reach
exactly one address and nothing else. The `api` tier cannot be restricted that way
— AWS service endpoints are not a fixed set — which is one more reason to prefer
`metadata` where it suffices.

It runs as root, which it does not need for capability: the served directory has to
be readable by the unprivileged HTTP server, and `DynamicUser` puts state under
`/var/lib/private` at mode 0700, where `nobody` cannot reach it.

**On the `api` tier the host holds account-wide read of the account's network
topology.** That is a real increase in what a compromised host can enumerate, it
cannot be scoped away, and it should be weighed per host rather than granted
fleet-wide.

## Implementation Details

- **Module**: `modules/nixos/services/service-hasp.nix`
- **Profile**: `pkgs.writeText` over `builtins.toJSON`, pure, no runtime step
- **Hash**: `builtins.hashString "sha256"` over fact values, truncated to 64 bits
  — a change-detection token read by humans, not a security digest. Invalidation
  does not depend on it: verdicts compare fact values directly
- **Collector**: Python 3 for the `metadata` tier — stdlib only, IMDSv2 token
  flow, no AWS SDK. `boto3` is added to the interpreter only on the `api` tier,
  where it handles instance-profile credentials, retries and pagination;
  hand-rolling SigV4 for six calls is exactly the kind of thing that breaks subtly
- **Registry manifest**: `hasp-registry.json` in the closure, so the collector can
  enforce the registry on facts produced after evaluation
