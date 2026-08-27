---
# elastinix-rx7o
title: 'HASP framework: per-host attack surface profile for CVE triage'
status: completed
type: task
priority: high
created_at: 2026-08-27T10:46:45Z
updated_at: 2026-08-27T10:56:02Z
parent: elastinix-p9gu
openspec-link: openspec/changes/archive/2026-08-27-hasp-framework
---

Corrected scanning leaves the fleet with **449 distinct CVEs**, none on the CISA KEV list and one above EPSS 0.10. The technical position is good and the reported position looks alarming, and there is no mechanical way to answer the question an auditor will ask: *which of these can actually hurt this machine, and how do you know?*

Answering it needs per-machine context no scanner has. A CVE against `postgresql-17.10` — 26 findings, joint-largest package on compute2-prod — means something entirely different when the socket is bound to `127.0.0.1` than when it is reachable from the internet, and nothing collected today records which.

A **Host Attack Surface Profile** is that context, published per machine and re-checkable when the machine changes.

## Scope

The evidence layer only. No triage decisions, no verdicts, nothing hidden. The registers, VEX records, `depends_on` invalidation and any model-drafted justification consume these documents and are separate work — none of it can be built until the documents exist.

## Three documents, split by how facts change

Not by subject matter. A fact folded into a hashed document changes that document's hash, so a fact that changes every five minutes would invalidate every verdict continuously.

| document | changes when | hashed |
| --- | --- | --- |
| `hasp.json` | the machine is rebuilt | yes |
| `hasp-aws.json` | the on-host collector runs, on a timer | no |
| `runtime-facts.json` | continuously, on a timer | no |

All three served by hostinfo on port 3333.

## 1. The static profile

Evaluated at build time into a single store path — no generator service, no timer, no generation timestamp. A closed, versioned fact registry: an unregistered key, a source that disagrees, or a value type that disagrees fails the build, because verdicts reference facts by key and a typo would produce a verdict that silently never invalidates.

Declared facts have **no defaults**. A `dataClassification` defaulting to `internal` is not a missing value; it is a false claim, made by nobody, that will be cited in an audit.

`haspHash` covers fact *values* only — not evidence strings, not the review stanza — so correcting a resource id or re-confirming a review never invalidates a verdict.

Measured constraint that shaped the registry: a stock NixOS system has 163 unit files of which 47 run as root, almost all nixpkgs-owned. A "units running as root" fact would churn on every nixpkgs bump and invalidate verdicts for reasons unrelated to exposure. Facts about what actually runs are therefore observed, not derived.

## 2. Infrastructure facts, collected on the machine

From the live AWS API rather than Terraform state — state records what Terraform last believed. Tiered by credential cost, because that cost is not scopable:

| tier | facts | IAM | closure |
| --- | --- | --- | --- |
| `metadata` | security group ids, subnet, public-IP presence | **none** | unchanged |
| `api` | + ingress rules, reachable-from-groups, subnet tier, load balancer, volumes | account-wide `ec2:Describe*` | +122 MB (boto3) |

EC2 describe actions do not support resource-level permissions, so an `api`-tier host cannot be granted "read my own security groups" — it gets account-wide read of every security group, subnet and route table. The `metadata` tier needs no credentials at all and covers the two highest-consequence exposures, so `api` is opted into per host for detail rather than being the price of entry.

What `api` uniquely buys is `network.reachableFromGroups`. A host with no `0.0.0.0/0` ingress previously read as unreachable when it may be reachable from the jumphost by every engineer in the company — the fact most likely to change a verdict.

Change detection falls out of collection: each run is diffed against the previous document, a changed fact is reported to the journal as `ATTACK SURFACE CHANGED` with before and after values, and the unit exits non-zero so it is alertable. This replaced a separate self-check — a collector that re-reads reality every interval already knows when reality changed.

A failed collection keeps the previous document and fails the unit. A partial document's missing fact reads as an absent risk; staleness is detectable from `lastCollected`.

## 3. Socket and unit-user observation

Added to the existing in-use sampler. Bind address is the point: a service bound to `127.0.0.1` is unreachable from anywhere else whatever the security group says, and neither the Nix configuration nor the AWS API can state which address a process bound to.

`bindClass` is `loopback`/`wildcard`/`specific`, kept beside the raw address. Two classifications that change the answer, both found against real socket tables: `[::]` is wildcard rather than IPv6-only, since such a socket accepts IPv4 unless `v6only` is set; and `::ffff:127.0.0.1` is loopback, observed live from Neo4j, where reading it as `specific` would forfeit the strongest available claim.

Negative claims must cite the cumulative observed set, never the current snapshot: a socket observed once proves only that it was bound then, and a listener that binds briefly under load would be absent from most samples.

`units.user` maps a unit to the list of users observed, because a unit whose main process is root and drops privileges in a child would lose the root fact if collapsed. Joined against in-use data it yields what neither document produces alone: *openssl-3.6.0 is executed by `quiqr-server.service`, which runs as root, in a process listening on all interfaces.*

## Fleet-constant facts

Measured against the repository: `fail2ban` is unconditional in `base-system.nix`, and auditd and central log shipping are absent entirely. Five facts had no variance across hosts and none over time, so they cannot discriminate between findings — they are fleet assertions, not per-host facts, and are carried in a separately-hashed `fleet` section. Three of the five are `false`, which makes the group read as a to-do list rather than evidence of controls. Publishing it is the point.

## Out of scope

- The triage engine, registers, VEX verdicts and invalidation
- Reducing actual exposure. Trimming `postgresql` and `vim` from `environment.systemPackages` (−46 distinct) and fixing the stale flake pins (−141 distinct) remain the highest-value security work available and are unaffected by this
- Container image facts; `docker-images.json` exists but trivy findings are not joined to container-level context
