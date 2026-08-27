# CHANGELOG

## Next version

### Added
- **Host Attack Surface Profile (`elastinix.hasp`)** — a static, content-hashed per-host fact document describing how a machine is exposed, served by hostinfo as `hasp.json`. It answers one question — given that a package is vulnerable, what about *this machine* makes that matter — and contains no CVEs, verdicts or scores. See [docs/services/hasp.md](docs/services/hasp.md) and [docs/hasp-framework.md](docs/hasp-framework.md)
  - **Pure and static**: evaluated at build time into a single store path. No generator service, no timer, and no generation timestamp — a pure store path has no build clock, and a fabricated one would be the only untrustworthy field in the document
  - **Closed, versioned fact registry**: an unregistered key fails the build. Verdicts will reference facts by key, so a typo (`publicIPAttached` for `publicIpAttached`) would otherwise produce a verdict that silently never invalidates
  - **No defaults for declared facts**: a missing `dataClassification` fails the build rather than substituting `internal` — a value nobody chose that would nonetheless be cited in an audit
  - **`haspHash` covers fact values only**, not `evidence`, `source` or the review stanza, so correcting a resource id or re-confirming a review never invalidates a verdict. Fleet-constant facts are carried in a separately-hashed `fleet` section: measured against the repo, `fail2ban` is unconditional and auditd and log shipping are absent entirely, so five facts had no per-host variance at all
  - **AWS facts collected on the machine** (`awsFacts`, default `"none"`), on a timer, from the live AWS API rather than Terraform state — state records what Terraform last believed. Published as `hasp-aws.json` and deliberately **not** part of `hasp.json`: facts that change without a rebuild would either freeze a stale value into the hashed profile or rehash it on every collection
  - **Tiered by credential cost.** `"metadata"` reads the instance metadata service for the security group set, subnet and public-IP presence, and requires **no IAM whatsoever** while adding nothing to the closure. `"api"` adds ingress rules, group-referenced reachability, subnet tier, load balancer attachment and volumes, at the price of account-wide `ec2:Describe*` — EC2 describe actions do not support resource-level permissions, so the grant cannot be scoped to the resources a host owns — plus ~120 MB of closure for boto3 (measured 209 → 331 MB)
  - **`network.reachableFromGroups`**: a host with no `0.0.0.0/0` ingress previously read as unreachable when it may be reachable from a jumphost by every engineer in the company. This is the fact most likely to change a verdict, and the only reason to consider the `api` tier
  - **Change detection is a property of collection.** Each run is compared against the previous document; a changed fact is reported to the journal as `ATTACK SURFACE CHANGED` with its before and after values, and the unit exits non-zero so it can be alerted on. `lastChanged` per fact and `changedKeys` per transition make the document a drift record rather than a snapshot. This replaced a separate self-check — a collector that re-reads reality every interval already knows when reality changed
  - **A failed collection publishes nothing**: the previous document is kept and the unit fails. A partial document's missing fact reads as an absent risk, while staleness is detectable from `lastCollected`. An unreachable metadata service is a failure, not agreement
  - **The registry is enforced at runtime too**: it is emitted into the closure as `hasp-registry.json` and the collector validates its own output against it, refusing to write on an unregistered key, a disagreeing type or an unsorted list
  - On the `metadata` tier the unit carries `IPAddressDeny=any` with `IPAddressAllow=169.254.169.254/32` — it can reach exactly one address and nothing else. The `api` tier cannot be restricted that way, since AWS service endpoints are not a fixed set
- **Socket observation (`hostinfo.enableSocketObservation`)** — the in-use sampler also records listening sockets with their bind address, and the user each unit actually runs as, exposed as `runtime-facts.json`
  - **Bind address is the point**: a service bound to `127.0.0.1` is unreachable from anywhere else whatever the security group says. `postgresql-17.10` is the joint-largest package on compute2-prod at 26 CVEs, and "nothing outside this machine can reach it" is a far stronger claim than "5432 is not in the firewall list". Neither the Nix configuration nor the AWS API can state which address a process bound to
  - `bindClass` is `loopback`/`wildcard`/`specific`, kept beside the raw address. `[::]` is wildcard rather than IPv6-only, since such a socket accepts IPv4 too unless `v6only` is set; `::ffff:127.0.0.1` is loopback, observed live from Neo4j, and classifying it as `specific` would forfeit the strongest available claim
  - **Negative claims must use the cumulative `observed` set**, not the `current` snapshot: a socket observed once proves only that it was bound then, and a listener that binds briefly under load would be absent from most samples
  - `units.user` maps a unit to the **list** of users observed, because a unit whose main process is root and drops privileges in a child would lose the root fact if collapsed. Joined against in-use data it yields what neither document produces alone: *openssl-3.6.0 is executed by `quiqr-server.service`, which runs as root, in a process listening on all interfaces*
  - `inuse.json` is now a projection of the same accumulating state and keeps its original shape, so existing consumers are unaffected. On first run, state is seeded from an existing `inuse.json` — months of samples are the observation window every "never observed" claim rests on
  - `AF_NETLINK` is granted to the sampler only when socket observation is enabled: `ss` queries `sock_diag` over netlink, and denying it would return nothing while exiting successfully — the same silent blindness as hiding `/proc`
- **In-use code sampling** — vulnerability findings can now be split by whether the affected package's code has actually been observed executing. A CVE against a package says only that the package is present; this answers whether it runs, which is the evidence needed to argue a finding is not exploitable.
  - **`hostinfo.enableInUseSampler`** (default `false`) — a timer samples `/proc/<pid>/maps`, `/proc/<pid>/exe` and `/proc/<pid>/cmdline` every `inUseSamplerIntervalSeconds` (default 300), accumulating into `inuse.json` served over the hostinfo port. All three sources are required: `maps` + `exe` alone observed 62 store paths on a live host, 71 with `cmdline` included
  - Records per package the sample count, last-seen time, and the **systemd units** holding it — turning an inference into an observation: `openssl-3.6.0` is loaded by `quiqr-server.service`
  - The central scan fetches and persists each host's document beside its `output.json`, so findings and their supporting evidence share a directory and a timestamp
  - **`inuse` label** on `vulnix_vulnerabilities_total` with values `true`/`false`/`unknown`, plus `vulnix_inuse_sample_count` and `vulnix_inuse_last_sample_timestamp` so the strength of a `false` is visible beside it
  - Absent, unparseable, stale or gapped data resolves to `unknown`, **never** `false` — a dead sampler must not make unobserved code look safe. Staleness is measured against the document's fetch time, not wall-clock now, because the scan runs weekly
  - The sampler runs as root and deliberately omits `ProtectProc`/`PrivateUsers`: either hides other processes from `/proc`, leaving the sampler blind while still exiting successfully
  - **Reading it honestly**: the observed set only grows, so `inuse="false"` counts will fall over time as rarely-executed code is caught. At a five-minute cadence "never observed" means "never observed at this cadence" — short-lived processes are not reliably caught
  - First measurement on compute5: 75 packages observed of 907 in the closure; 72 CVE-instances in use, 204 not in use

### Fixed
- **CVE overcounting in vulnerability reports**: reports overstated findings by ~1.8x. On `compute5-prod` the exporter published 471 CVE-instances where the scan found 259 distinct CVEs; after these fixes it reports 276 instances / 248 distinct. On `compute2-prod`, 361/215 becomes 211/206.
  - **Multi-output deduplication** (`deduplicateOutputs`, default `true`): outputs of one derivation were counted separately, so `openssl-3.6.0`, `-bin` and `-dev` each contributed 37 CVEs. Findings are now grouped by package name with output suffixes stripped, and grouped CVE sets are **unioned** — never replaced, because two builds of the same version can carry different patch coverage (`compute5-prod` has a patched and an unpatched `libssh2-1.11.1`, and picking either alone would hide four real CVEs)
  - **CPE vendor exclusion** (`cveVendorExclusions`): vulnix matches NVD advisories on the CPE product string alone and ignores the vendor, so every reported `git` CVE was actually a Jenkins Git Plugin or Git for Windows advisory. Also affected `dash` (Plotly), `zlib` (Cloudflare fork, Ruby gem) and `go` (the `ecies` library). Implemented as a disallow list that fails open — gawk's genuine advisories carry CPE vendor `fossies`, so a permit list would have discarded real bugs
  - **Local vulnix patch** (`patches/vulnix-emit-cpe-vendors.patch`): vulnix discards the CPE vendor it parses, so the scan now emits `cpe_vendors` in its JSON output. Applied via overlay from `vulnerability-scan-central`; deliberately not contributed upstream. Reading an unpatched `output.json` logs a warning and excludes nothing
  - **`vulnix_distinct_cves_total`**: new gauge counting each CVE once per host. Use it for reporting and audit evidence; `vulnix_vulnerabilities_total` remains the per-affected-package count for remediation planning
  - Host enumeration now requires a directory, so leftovers from the retired local scan service (`/var/lib/vulnix/output.json`, `cache/`) are no longer treated as hosts
  - **Note**: `vulnix_vulnerabilities_total` drops ~44% with no change in scan coverage. Re-baseline dashboards and alert thresholds; this is a counting-accuracy fix, not remediation
- **vulnix-scan bootstrap op t3.small**: service werkte niet op instances met weinig RAM (1.9GB, geen swap) — initiële NVD cache-opbouw werd afgebroken door OOM killer
  - Bootstrap-mechanisme: bij lege cache tijdelijk 1.5GB swapfile aanmaken, NVD database opbouwen (~2 min), swapfile verwijderen
  - Disk-check vooraf: minimaal 2GB vrij vereist; anders overgeslagen met waarschuwing
  - `ExecStopPost` ruimt swapfile op bij onverwacht afbreken
  - Cache verplaatst van `/var/lib/sbom/cache` naar `/var/lib/vulnix-cache` (scheiding verantwoordelijkheden)

### Changed
- **vulnix-scan packages.json**: service genereert packages.json niet meer zelf via `nix-store -qR`; leest `/var/lib/sbom/packages.json` dat door de deploy-wrapper aangeleverd wordt bij elke deployment

### Added
- **Central vulnerability scanning** (ISO 27001): Architecture shift from local per-host scanning to centralized scanning on a dedicated scanner host
  - **`hostinfo.enableInventory`**: Existing inventory service now behind an explicit option (default `true`, backwards-compatible) — set to `false` to disable `services.json` generation
  - **`hostinfo.enablePackages`**: New option (default `false`) — exposes `/var/lib/packages/packages.json` (uploaded by Terraform) via hostinfo HTTP port
  - **`hostinfo.enableDockerImages`**: New option (default `false`) — daily Docker inventory via Docker socket, exposes `docker-images.json` via hostinfo HTTP port
  - **`vulnerability-scan-central`**: Combined central scanner replacing separate `vulnix-scan-central` and `trivy-scan-central` services; vulnix runs for all hosts, trivy runs per-host via `enableDockerScan = true`
    - `vulnixCacheDir` option (default `/var/lib/vulnix-cache`) — configurable NVD cache location
    - `trivyCacheDir` option (default `/var/lib/trivy-cache`) — configurable trivy DB cache, required to work within systemd `ProtectSystem = "strict"` hardening
  - **`vulnerability-prometheus-exporter`**: Prometheus exporter on port 9200 that reads vulnix and trivy scan results and exposes per-host severity metrics for Grafana dashboards and alerting

### Fixed
- **`vulnerability-scan-central` trivy DB download**: trivy tried to write its vulnerability DB to `/root/.cache` which is read-only under systemd hardening — fixed by passing `--cache-dir` to a writable path (`trivyCacheDir`)
- **`vulnerability-scan-central` scan continuity**: script used `set -euo pipefail` causing the entire scan to abort on any single failure — replaced with per-command error handling; failed hosts/images are logged and counted, scan always completes
- **`vulnerability-scan-central` warnings not counted**: curl failures (unreachable hosts, HTTP non-200) were logged but not counted — scan completion line now shows `Warnings: N, Errors: M` so unreachable hosts are visible in the summary

### Changed
- **`vulnix-scan` removed**: Local per-host vulnix scanner replaced by `vulnerability-scan-central` — see `docs/services/vulnix-scan.md` for migration guide

- **Jira Ticket Create service**: Scheduled Jira ticket creation per client and check type
  - Define reusable check types once (schedule, title template, description, issue type, due date offset)
  - Apply check types to multiple clients; generates one systemd timer+service per client×check combination
  - Structured schedule values: `first_working_day_of_month`, `first_working_day_of_quarter`, `first_working_day_of_week`, `every_working_day`
  - Raw systemd calendar schedules via `schedule = { calendar = "Thu *-*-* 08:00:00"; }`
  - `{period}` placeholder in title templates replaced at runtime (e.g. `2026-Q2`)
  - Per-client Jira URL/user overrides for multi-instance setups
  - Jira API token via agenix secret per client
  - Standard elastinix systemd hardening applied to all generated services

### Fixed
- **Jira Ticket Create service**: ticket description now supports multiline Nix strings — JSON payload is assembled via `jq` instead of a bash heredoc, making all fields safe against newlines, quotes, and special characters

### Changed
- **Jira Ticket Create service** (**BREAKING**): `frequency` and `timerCalendar` options replaced by a single `schedule` option
  - Migration: replace `frequency = "..."` with `schedule = "..."`
  - Migration: replace separate `timerCalendar = "..."` with `schedule = { calendar = "..."; }`
- **Documenso service**: Pure NixOS module for open-source document signing platform
  - Supports external PostgreSQL with automatic Prisma migrations
  - BullMQ/Redis integration for scheduled signing reminders
  - S3-compatible storage for PDF documents
  - SMTP email integration with Postfix relay support
  - Auto-generate or provide custom PDF signing certificates (PKCS#12)
  - Full agenix/sops-nix secret management with *File options
  - Systemd security hardening (NoNewPrivileges, ProtectSystem=strict)
  - Comprehensive NixOS VM test suite with 10 validation tests
  - Complete documentation with deployment, upgrade, and troubleshooting guides

## Elastinix nixos-25.05.2 - 30 September 2025

- new versioning system bound to official nixos releases
- minimal remote functions
- many small bugfixes
- initial usage documentation in README.md
- new logo

## Elastinix v0.1.0

- mini intro
- initial module setup
- initial start of exporting funtions
- implement flake-parts
