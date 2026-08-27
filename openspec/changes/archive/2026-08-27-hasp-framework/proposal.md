Task: [.beans/elastinix-rx7o--hasp-framework-per-host-attack-surface-profile-for.md](../../../.beans/elastinix-rx7o--hasp-framework-per-host-attack-surface-profile-for.md)

## Why

Corrected scanning leaves the fleet with **449 distinct CVEs**, none on the CISA
KEV list and one above EPSS 0.10. The technical position is good and the reported
position looks alarming, and we currently have no mechanical way to answer the
question an ISO 27001 auditor will ask: *which of these can actually hurt this
machine, and how do you know?*

Answering it needs per-machine context that no scanner has. A CVE against
`postgresql-17.10` — 26 findings, joint-largest package on compute2-prod — means
something entirely different when the socket is bound to `127.0.0.1` than when it
is reachable from the internet, and nothing we collect today records which.

This change builds the evidence layer only. It makes no triage decisions, files
no verdicts and hides no findings.

## What Changes

- **Three per-host fact documents**, split by how each fact can change, all served
  by `hostinfo` on port 3333:
  - `hasp.json` — static, content-hashed, evaluated at build time. Declared
    intent, configuration projections, infrastructure exposure. The document a
    triage verdict cites and can be reconstructed from.
  - `hasp-aws.json` — infrastructure facts collected **on the machine** on a
    timer, from the live AWS API rather than Terraform state. Not hashed,
    because they change without a rebuild.
  - `runtime-facts.json` — observed, refreshed on a timer, deliberately not
    hashed.
- **A closed, versioned fact registry.** An unregistered key fails the build,
  because verdicts will reference keys by name and a typo would produce a verdict
  that silently never invalidates.
- **Declared facts have no defaults.** A `dataClassification` that defaults to
  `internal` is a false claim, made by nobody, that would be cited in an audit.
  Missing declaration is a build failure.
- **Infrastructure facts collected on the machine**, on a timer, from the live
  AWS API rather than Terraform state — state records what Terraform last
  believed. Split into two tiers by credential cost: `metadata` reads the
  instance metadata service and needs **no IAM whatsoever**, while `api` adds
  ingress rules, group-referenced reachability, subnet tier, load balancer
  attachment and volumes at the price of account-wide `ec2:Describe*`, because
  those actions cannot be scoped to the resources a host owns.
- **Change detection falls out of collection.** A collector that re-reads reality
  every interval *is* the drift detection: each run is compared against the
  previous document, and a changed fact is reported to the journal with its
  before and after values. Nothing is ever reconciled — the collector writes only
  its own document.
- **Socket and unit-user observation** added to the existing sampler: bind
  address classified as `loopback`, `wildcard` or `specific`, attributed to the
  owning unit and user. Neither the Nix configuration nor the AWS API can state
  which address a process bound to; it has to be measured.
- **Fleet-constant facts are separated** into a `fleet` section with its own
  hash. Measured against the repository, `fail2ban` is unconditional at
  `base-system.nix:5`, and auditd and central log shipping are absent entirely —
  five facts with no variance across hosts, which were being presented as
  per-host.

Not in scope, tracked separately: the triage engine, the not-affected and
accepted-risk registers, VEX verdict records, `depends_on` invalidation, and any
model-generated justification. Those consume these documents; none of them can be
built until the documents exist.

## Capabilities

### New Capabilities

- `hasp-host-profile`: the static, content-hashed per-host fact document — fact
  record shape, the closed registry, the declared block with review metadata,
  hashing rules, and build-time validation.
- `hasp-aws-facts`: on-host collection of infrastructure facts from instance
  metadata and the live AWS API, tiered by credential cost, validated against the
  registry at runtime.
- `hasp-drift-verification`: change detection as a property of collection — each
  run compared against the previous document, changed facts reported with their
  before and after values, and failure kept distinguishable from no-change.
- `hostinfo-socket-observation`: observation of listening sockets with bind
  classification and unit/user attribution, its staleness contract, and the
  cumulative-versus-current distinction that governs negative claims.

### Modified Capabilities

- `hostinfo-service`: gains requirements for serving the three HASP documents,
  including that `hasp.json` and `hasp-aws.json` are symlinks into a single store
  path rather than externally uploaded files.

## Impact

**Code**

- `modules/nixos/services/service-hostinfo.nix` — three new served documents,
  and the socket/unit-user observation added to the existing in-use sampler.
- A new `elastinix.hasp` module implementing the registry, the declared block,
  hashing and validation.

**Cross-repo dependency**

The AWS collector runs in the deploy pipeline in the workloads repo, which is the
only place that both holds AWS credentials and runs evaluation — the hosts have no
derivers, which is the same constraint that makes `vulnix --system` fail. This
change defines the contract its output must satisfy; the collector itself must be
proposed there.

**Security**

Each host gains a served description of its own attack surface. This sits behind
the same trust boundary that already carries `services.json` and `packages.json`,
which between them list every enabled service and every installed package with
versions. No new IAM is granted to any host: collection uses existing pipeline
credentials, and the on-host check uses credential-free instance metadata. This is
deliberate — EC2 `Describe*` actions do not support resource-level permissions, so
granting them per host would mean account-wide network read on every machine.

**Reporting**

No metric changes. `vulnix_vulnerabilities_total` and the `inuse` label are
untouched. New documents are additive.

**Coordination**

`fix-cve-overcounting` and `in-use-code-sampling` are both in progress and both
carry deltas against `vulnerability-prometheus-exporter`. This change touches
neither that capability nor `hostinfo-inuse-sampler`, and `hostinfo-socket-observation`
is deliberately a separate capability covering sockets and unit users only, so
there is no overlapping delta.

`openspec/specs/hostinfo-service` currently contains an *Optional SBOM exposure*
requirement describing an option that no longer exists. Out of scope here, but it
should be removed by whichever change next deltas that capability.
