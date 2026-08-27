## Context

Central vulnerability scanning runs on `compute5-prod`, fetching `packages.json`
from each host's hostinfo server and running vulnix per host. After the counting
corrections the fleet reports **449 distinct CVEs**, of which zero are on the CISA
KEV list and one exceeds EPSS 0.10.

The scan can say a package is present. It cannot say whether that matters here.
Measured on the two instrumented hosts, the in-use sampler already splits findings
by whether code executes:

| Host | Findings on code observed executing | Never observed |
| --- | --- | --- |
| compute5-prod | 82 | 178 |
| compute2-prod | 71 | 140 |

That is one dimension of exposure, collected empirically. This change generalises
it: a per-host fact set covering network reachability, declared intent,
configuration and runtime behaviour, from which triage decisions can later be
derived and — crucially — re-derived when the machine changes.

Constraints:

- **Evaluation does not happen on the hosts.** The deploy copies runtime paths
  without derivers, which is the same reason `vulnix --system` and `--closure` fail
  there. Anything a fact needs at evaluation time must therefore come from the
  configuration, which is why facts about live infrastructure are collected at
  runtime instead.
- **EC2 `Describe*` actions do not support resource-level permissions.**
  `DescribeSecurityGroups` cannot be scoped to "my own groups"; granting it means
  account-wide read.
- `compute5-prod` has 3.8 GB RAM and the last scan peaked at 1.9 GB. Nothing here
  may run inside the scan's memory envelope.
- The hostinfo HTTP server runs as `nobody:nogroup` with `ProtectSystem=strict`.
- No secrets are involved anywhere in this change. Instance metadata requires no
  credentials, and the collector uses the pipeline's existing ones, so **agenix is
  not used** and no age secret is introduced.

## Goals / Non-Goals

**Goals:**

- A per-host fact set rich enough to support the VEX justifications we can
  honestly claim, and explicit about the ones we cannot.
- Facts that are re-checkable: a verdict decided under one state of the world must
  be detectably stale when the world changes.
- Bounded staleness on the facts that carry the most weight, rather than
  unbounded drift acknowledged in a footnote.
- Nothing becomes invisible without a retrievable reason.

**Non-Goals:**

- The triage engine, the registers, VEX verdict records, and any model-generated
  justification. This change produces inputs only.
- Reducing actual exposure. Trimming `postgresql` and `vim` from
  `environment.systemPackages` (−46 distinct) and fixing the stale flake pins
  (−141 distinct) remain the highest-value security work available and are
  unaffected by this.
- Changing scan scope, schedule or invocation.
- Container image exposure. `docker-images.json` exists; joining trivy findings to
  container-level facts is separate.

## Decisions

### Split the facts into three documents by rate of change

Not by subject matter. A fact folded into a hashed document changes that
document's hash, and a fact that changes every five minutes would invalidate every
verdict continuously.

| Document | Changes when | Hashed |
| --- | --- | --- |
| `hasp.json` | the machine is rebuilt | yes |
| `hasp-aws.json` | the collector runs at deploy | it is an input to the above |
| `runtime-facts.json` | continuously, on a timer | no |

*Alternative rejected:* one document. It forces a choice between excluding runtime
observation — which is where the strongest evidence lives — and rehashing every
five minutes.

### Query the live AWS API, not Terraform state

State records what Terraform last believed. The API records what is. Reading state
would make the profile agree with our intentions rather than with reality, which is
the failure being eliminated rather than formalised.

### Collect on the machine, not in the pipeline

The collector runs as a timer on each host and publishes `hasp-aws.json` beside the
static profile.

The consequence to be explicit about: EC2 `Describe*` actions **do not support
resource-level permissions**, so an `api`-tier host cannot be granted "read my own
security groups" — it gets account-wide read of every security group, subnet and
route table in the account. That is a real expansion of what a compromised host can
enumerate, and it is the price of this placement.

It is bounded by tiering the fact set on credential cost:

| Tier | Facts | IAM | Closure |
| --- | --- | --- | --- |
| `metadata` | security group ids, subnet id, public-IP presence | **none** | unchanged |
| `api` | + ingress rules, reachable-from-groups, subnet tier, load balancer, volumes | account-wide `ec2:Describe*` | +~120 MB (boto3) |

A host on the `metadata` tier publishes real, current network facts while holding
no permissions at all, because instance metadata is credential-free. That covers the
two highest-consequence exposures — the attached group set, and a public IP
appearing — so the `api` tier is an opt-in for detail rather than the price of
entry.

*Alternative rejected:* pipeline-side collection writing into the stack directory
before evaluation. It needs no host IAM and keeps both documents in one closure,
but the facts are then only as current as the last deploy, the collector output has
to be git-tracked for Nix to see it at all, and a deploy mutates the configuration
repository.

### Infrastructure facts leave the hashed profile

Since they now change without a rebuild they cannot live in `hasp.json`: hashing
them would either freeze a stale value into the profile or rehash it on every
collection.

This costs the "cannot disagree" property a single closure gave, and buys currency.
Verdict invalidation is unaffected, because verdicts remember fact *values* and
compare them against whichever document currently carries the key — the mechanism
never required the two to share a document.

### Change detection is a property of collection, not a separate check

A collector that re-reads reality every interval already knows when reality
changed. So it compares each collection against the previous document, records
`lastChanged` per fact and `changedKeys` for the latest transition, and reports a
change to the journal with before and after values, exiting non-zero so it can be
alerted on.

This removes a unit rather than adding one: a separate self-check comparing
metadata against the static profile has nothing left to compare.

*What is lost:* the daily pipeline-side comparison was an independent check that a
host's view matched the account's. With the host querying the API itself its view
*is* the account's view, so the remaining question is only whether the collector is
running — which `lastCollected` answers.

### A failed collection publishes nothing

On any error the collector keeps the previous document and exits non-zero rather
than writing the facts it managed to obtain. A partial document is worse than a
stale one, because an absent fact reads as an absent risk while a stale document is
detectable from `lastCollected`.

### Projections, not enumerations

Measured on a stock NixOS system: 163 unit files, 114 loaded services, 47 with no
`User=`. A `rootUnits` fact would be ~47 entries, almost all nixpkgs-owned, and a
nixpkgs bump would change it — invalidating verdicts for reasons unrelated to
exposure.

"Config, not closure" is not a clean line, because NixOS *modules* define units, so
a fact reading `config` can still be downstream of package versions. The rule
becomes: read our own namespace plus a whitelist of upstream options, and emit a
projection that answers a question rather than a list of what exists.

Where completeness demands the closure — a host with `services.postgresql.enable`
set directly is invisible to `elastinix.*` and plainly present in the closure —
project the closure down to the question. Under-reporting attack surface is the
wrong direction to be wrong in.

### Observe sockets and unit users rather than deriving them

Bind address is the single most verdict-changing fact available, and it is not
derivable at all. `postgresql-17.10` carries 26 findings on compute2-prod; the
static profile can only say "5432 is not in the firewall list", while an observed
`127.0.0.1` binding supports the far stronger *"nothing outside this machine can
reach it."*

This also replaces `rootUnits` with an observed `units.user` map: complete rather
than namespace-limited, unhashed so nixpkgs churns nothing, and in the same
document as the `units` field it must join against.

The sampler extension inherits the existing unit's hardening posture, including the
constraint that it must **not** set `ProtectProc` or `PrivateUsers` — either hides
other processes from `/proc`, so the sampler would observe nothing while still
exiting successfully.

### Negative claims must cite cumulative observation

A package observed once proves it executes. A socket observed once proves only
that it was bound *then*. So `sockets` records both a cumulative `observed` map and
a `current` snapshot, and a negative claim ("never externally bound") may only cite
the cumulative set. A service binding an external listener under load would be
missed by any snapshot, and granting unreachability on that basis is precisely the
silent-wrongness this framework exists to prevent.

### Verdicts will remember values, not key names

Recorded here because it constrains the document format even though verdicts are
out of scope. A verdict stores the *values* of the facts it relied on, making
staleness a direct comparison against the current documents:

```
for (key, remembered) in verdict.depends_on:
    if current_value(key) != remembered:  → stale
```

*Alternative rejected:* the scanner storing previous profiles and diffing them.
That is wrong on first run, wrong after any scanner rebuild, wrong for a host
skipped last week, and makes correctness depend on a cache surviving.

Two consequences the documents must support: every fact value must be
JSON-comparable, and a removed registry key must read as absent rather than
erroring — which is also why registry evolution needs no deprecation tombstones.

### Separate fleet-constant facts, hashed separately

Measured: `fail2ban` is unconditional at `base-system.nix:5`; auditd and central
log shipping are absent from `modules/` entirely; ssh settings are nixpkgs
defaults. Five facts with no variance across hosts and none over time cannot
discriminate between findings, and duplicating them into six profiles pretends
otherwise.

They are not worthless — a fleet-wide fail2ban regression should invalidate every
verdict that leaned on it — they are fleet assertions, not per-host facts.

Carried as a separately-hashed `fleet` section rather than a seventh document.
Invalidation is value-based, so correctness does not depend on the split; a
separate file would need its own distribution and freshness path for no gain.

### The hash covers values only

Not `evidence`, not `source`, not the review stanza. Correcting a resource id in an
evidence string, or re-confirming a declaration on a new date, changes nothing
about exposure and must not invalidate a verdict. Reviewing a profile should never
be discouraged by the cost of reviewing it.

### Drop the `access.*` group

`instanceProfilePolicies`, `interactiveUsers`, `sshPasswordAuthentication` and
`sshPermitRootLogin` were drafted and cut: no justification cites any of them, and
the first two are the most sensitive fields in a document served unauthenticated.
The test applied — and to be applied to any future addition — is that a fact no
justification depends on is decoration.

## Risks / Trade-offs

- **The `api` tier grants account-wide network read to every host using it.** →
  Not mitigable through IAM scoping, because EC2 describe actions do not accept
  resource ARNs. Mitigated only by tiering: `metadata` needs no permissions at all
  and covers the highest-consequence facts, so `api` is opted into per host rather
  than enabled fleet-wide by default.
- **A failed collection leaves a stale document.** → Deliberate: the previous
  document is kept and the unit fails, since a partial document's missing fact
  reads as an absent risk. `lastCollected` makes staleness detectable and consumers
  resolve affected claims to unknown.
- **Instance metadata may be unreachable or IMDSv1-disabled.** → Collection fails
  loud. A collector that cannot run must be distinguishable from one that found no
  change.
- **boto3 adds ~120 MB to the closure on the `api` tier.** → Measured (209 MB →
  331 MB). Confined to hosts that opt in; `metadata` uses only the standard
  library.
- **Sockets bound only briefly under load read as never externally bound.** →
  Cumulative observation errs in the safe direction, but the window is real. Open
  question; sample rate is the crude lever.
- **Serving a machine's attack surface unauthenticated.** → Same trust boundary
  that already carries `services.json` and `packages.json`, which list every
  enabled service and every installed package with versions. If hostinfo gains
  external exposure via bean `elastinix-n3zn`, authentication is a prerequisite,
  not a follow-up.
- **Three of the five fleet mitigation facts are `false`.** → This makes the group
  read as a to-do list rather than evidence of controls. Uncomfortable and correct;
  publishing it is the point.
- **The registry is a maintenance surface.** → Closed, versioned, and governed by
  the "no justification cites it, drop it" test. Growth is a review question, not
  an accident.
- **The pipeline needs AWS read permissions it may not currently hold.** →
  Enumerated in tasks: `ec2:DescribeInstances`, `DescribeSecurityGroupRules`,
  `DescribeRouteTables`, `DescribeVolumes`, `elasticloadbalancing:DescribeTargetGroups`,
  `DescribeTargetHealth`. All read-only.

## Migration Plan

1. Land the `elastinix.hasp` module with declared and derived facts only
   (`awsFacts = "none"`). Every host can build immediately.
2. Add socket and unit-user observation to the sampler. Independent of the above
   and immediately useful — a loopback-bound service is visible evidence the day
   it lands.
3. Enable `awsFacts = "metadata"` per host. No IAM change, no closure growth, real
   current network facts, and change reporting from the second collection onward.
4. Decide per host whether the `api` tier's detail is worth account-wide describe
   permissions, and raise the tier only where it is.
5. Alert on the collector unit failing and on `ATTACK SURFACE CHANGED` in its
   journal output.
6. Confirm: two collections of an unchanged instance report no change; a deliberate
   security-group attachment is reported within one interval with both values; a
   loopback-bound service is recorded as `loopback`.
7. Rollback: `awsFacts = "none"` removes the collector and its document;
   `enable = false` removes the profile too. Neither affects scanning, the
   exporter, or the in-use sampler.

## Open Questions

- **Sockets bound only under load.** Is there a cheaper signal than raising the
  sample rate — a `systemd.socket` unit inventory as a cross-check, perhaps, which
  would at least reveal declared socket activation?
- **Who owns the fleet section's judgement?** Its facts are derived and need no
  reviewer, but "we accept that auditd is off fleet-wide" is a decision somebody
  should own. A review stanza on the fleet block, or a separate risk acceptance?
- **Which database engines are worth encoding** in the `localDatabases` closure
  projection? Each needs writing per engine, and the value is in completeness, so a
  partial list has to be labelled as partial.
- **Is the `api` tier's fact set worth account-wide describe permissions on any
  host?** The `metadata` tier already covers the group set and public-IP presence.
  The `api` tier's distinctive contribution is `reachableFromGroups` — knowing a
  host is reachable from the jumphost rather than merely "not from the internet" —
  which is the fact most likely to change a verdict. Whether that justifies the
  grant is a security decision, not a technical one.
- **Should the collector's change report reach Prometheus rather than only the
  journal?** A unit failure is alertable today, but "which fact changed" is only in
  the journal text.
