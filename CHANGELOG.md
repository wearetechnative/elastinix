# CHANGELOG

## Next version

### Changed
- **State moved into the directory it is served from** (`hostinfo`, `hasp`, `vulnerability-scan-central`). Every document a service in these modules produces was written to its own `/var/lib` directory and symlinked into `/var/lib/hostinfo`, which meant six symlinks and two names for every fact. Writers now write where the file is served
  - `/var/lib/inuse-sampler/daily/` → `/var/lib/hostinfo/observations/`, `/var/lib/hasp/hasp-aws.json` → `/var/lib/hostinfo/hasp-aws.json`, `/var/lib/docker-inventory/images.json` → `/var/lib/hostinfo/docker-images.json`, and `/var/lib/vulnix-evidence/` → `/var/lib/vulnix/evidence/`
  - **`hasp.json` and `packages.json` stay symlinks, deliberately.** The first is a pure build product in the Nix store with no runtime state to place; the second is uploaded by Terraform, from outside NixOS entirely, and there the link *is* the interface between where the producer writes and where we serve. Removing it would have made `enablePackages` a no-op and broken the upload target
  - **`docker-images.json` is now written via a temporary file and a rename.** A truncating redirect into the served directory would let a consumer fetch an empty inventory mid-write and read it as "no images" — the same defect class as the vulnix output file
  - **The cost is wider write access:** a writer that renames into place needs the containing directory, so the AWS collector and the Docker inventory hold `ReadWritePaths=/var/lib/hostinfo` where they previously held only their own directory. The sampler stays narrow — it owns `observations/` outright
  - **Retention no longer names the evidence directory separately.** Now that it sits under the vulnix root, naming both visited every bundle twice and reported double what it removed. Verified: three stale artifacts across the tree report as three, not six
  - **Migration is manual and, for the observation records, order-critical.** tmpfiles will not replace an existing symlink with a directory and its remove pass runs only at boot, so on a deployed host `/var/lib/hostinfo/observations` stays a symlink into the old path — where `rm -rf` on the old directory destroys the records. `hasp-aws.json` heals itself because a rename over that path replaces the symlink; a directory symlink never does. The sampler now reports both failure modes on every run, excluding `index.json` from the count since it is rewritten every run and is not evidence. See the migration sections in [docs/services/hostinfo.md](docs/services/hostinfo.md) and [docs/services/vulnerability-scan-central.md](docs/services/vulnerability-scan-central.md)
- **The scan timer defaults to `daily` instead of `weekly`**, with jitter cut from 6 hours to 20 minutes. The scanned hosts seal one observation record a day and the scanner is what carries them to S3, so a weekly collector left a day sitting on its host for up to a week and a report written on the first of the month was missing the days that mattered most. Jitter buys nothing with a single scanner, while a six-hour window made it unpredictable whether the last day of a month had been collected by the time someone generated that month's report
  - **On a scanner that is stopped overnight, `daily` fires while the machine is off.** compute5-prod runs 04:30–20:00 UTC under `InstanceScheduler`, so the 00:00 trigger is always a `Persistent` catch-up at boot rather than a scheduled run. Pin `interval` to a time inside the uptime window (e.g. `"*-*-* 05:00:00"`) where that matters

- **In-use and socket observation moved to daily records** (`hostinfo.enableInUseSampler`). The sampler wrote one forever-growing document per host, so the window every "never observed" claim rested on was whatever had elapsed since the last deploy — the report said "never observed in 804 samples", which sounds like broad coverage and was 68 hours. It now writes one record per day, sealed when the day rolls over and never modified again, served under `observations/` with an `index.json` naming the sealed days. ISO reporting here is monthly, so a claim becomes *"not observed on any of the 31 days of August, every day complete"*, which an auditor can weigh
  - **A complete day is all *uptime* within the day**, not 24 hours of observation. compute5-prod is stopped 8.5 hours a night under `InstanceScheduler`; a 24-hour rule would mark it incomplete every day forever while its sampler works perfectly. Each sample reads `/proc/uptime`, so a gap shorter than the host's uptime is an unobserved gap that costs the day its completeness, while a gap longer than uptime is a reboot and costs it nothing
  - **One series instead of four**: each record also carries the `haspHash` in force that day and the `hasp-aws` values with their `changedKeys`, so a package, the declared attack surface and the AWS facts behind it are read from the same day
  - **The accumulating window machinery is gone** — `observedWindowSeconds`, `samplesInObservedWindow` and `observedWindowEpoch` existed only because observation never ended. Three defects came out with it: ephemeral client ports accumulating as listeners, a coverage numerator and denominator measured over different periods, and the epoch marker needed to repair a pair that had drifted. All three were found only after deploying; a record sealed at the end of its day has nothing to drift against
  - **The scanner fetches every sealed day it does not already hold** and uploads each to `<prefix>/daily/<host>/<date>.json`. A key that exists is a day already uploaded, so nothing tracks upload state and the run is idempotent. Retention lives on the bucket: the host prunes nothing and the scanner never deletes
  - **Coverage is derived identically by the normalizer and the exporter** — days examined, days complete — so a dashboard and a report cannot disagree about the same host. Verified across one complete day, zero complete days and no records at all. The exporter's `vulnix_inuse_sample_count` and `vulnix_inuse_last_sample_timestamp` are replaced by `vulnix_inuse_days_examined` and `vulnix_inuse_days_complete`, and `inUseStalenessBoundSeconds` is removed
  - **The superseded documents are deleted by the sampler**, not left to tmpfiles. Its remove pass runs only at boot, so on the deployed fleet — compute2-prod had 32 days of uptime — the hostinfo server kept serving a frozen `inuse.json` with a plausible `lastSample` and a sample count that would never move again. Measured on all three hosts: the old documents stopped at 13:08–13:12 while the new records took over at 13:13–13:17, and both were still served with HTTP 200. They are now removed within one sampler interval
  - **The existing cumulative evidence is discarded rather than migrated.** Two differently shaped sets of facts is worse than one gap. **Every host starts from an empty series, so for one day no host can support a negative claim and every finding reports `inUse: "unknown"`.** That is a deliberate, dated gap and must be recorded before the next monthly report — it is a measurement reset, not remediation and not a regression
  - **Deployment prerequisite outside this repository**: an S3 lifecycle rule expiring the `daily/` prefix after six months. The existing `s3:PutObject`-only policy already covers writing there, provided its resource is not scoped to `runs/*`. Roughly 20 kB per host per day, about 7 MB per host per year

### Added
- **Evidence bundle export (`vulnerability-scan-central`)** — each scan run is now normalized into one schema-versioned `evidence.json` and optionally uploaded to versioned S3, so ISO 27001 audit reports can be generated from a single immutable snapshot without live access to hosts or AWS. See [docs/services/vulnerability-scan-central.md](docs/services/vulnerability-scan-central.md)
  - **Timestamped snapshots**: vulnix and trivy results are additionally written as `output-<runId>.json`, so finding history survives a run and period-over-period reporting ("opened 14, closed 9") becomes possible. `output.json` keeps its path, so the Prometheus exporter is untouched
  - **Persistent scan log** per run at `/var/lib/vulnix-evidence/logs/scan-<runId>.log`, retained under the same policy and written even when the run ends with errors
  - **HASP artifacts fetched** per host: `hasp.json` and `hasp-aws.json`, each validated before storing so a truncated fetch never replaces a good copy
  - **Coverage is structural, not parsed**: `coverage.skipped` records every configured host that was not collected, with a reason, derived from the run's own fetch outcomes. A report cannot present partial collection as full assurance
  - **Per-source SHA-256** for every consumed artifact, so a report can cite a digest instead of reprinting a 500-row inventory and still bind the PDF to retrievable evidence
  - **Mirrors the exporter's finding semantics** — severity thresholds, multi-output grouping, vendor exclusion and in-use liveness guards — and reads `deduplicateOutputs` and `cveVendorExclusions` from the exporter's own config, so the bundle and the dashboards cannot be configured apart
  - **Write-only upload**: `s3:PutObject` and nothing else, with a conditional write so a colliding run id fails rather than overwriting. Withholding delete permission is what makes the evidence history tamper-evident rather than merely durable
  - **Upload failure is non-fatal**: the object is logged, the error counted, the local bundle retained, and the unit still exits 0 — the scan succeeded, and failing it would misrepresent collection as broken
  - **`snapshotRetentionDays` defaults to 180**, pruning by the run stamp in the filename rather than mtime. Six months is deliberate: these local files are the only copy of a run's raw inputs, so an uploaded bundle can only be re-normalized while they exist
  - **AWS CLI enters the closure only when upload is enabled** (~175 MB)
  - **`summary.packages` counts only packages carrying a reportable finding**, with `packagesFlagged` preserving the pre-exclusion figure. Found on the first real fleet run: 38 flagged but 34 reportable on compute2-prod, the gap being `git`, `dash` and `zlib`, whose every CVE the default vendor exclusions disown. An inflated count is worse in an audit document than no count
  - **`profile.haspSchemaVersion`** records the HASP document's own schema version, distinct from the bundle's, so a HASP format change stays traceable in archived evidence

### Fixed
- **In-use sampling coverage was measured against elapsed time, so any host on a stop/start schedule failed it permanently.** compute5-prod carries `InstanceScheduler = "6:30am-to-10pm-everyday"`: its 343 samples over a 70.3-hour calendar window read as 41% and were rejected, while the same samples against the ~44.8 hours it was actually running are 64%. The sampler was healthy — it produced 59 samples where 62 were due. All 137 of that host's critical and high findings therefore reported `inuse="unknown"`, 47% of the fleet total, and could not be assessed either way. The guard also failed in the other direction: a continuously running host whose sampler had died could pass, because elapsed and observed time were indistinguishable to it. The sampler now records observation per day and attributes each gap to downtime or to a stalled sampler using the host's own uptime, so a stop/start schedule costs a day nothing while a dead sampler still marks it incomplete (see *In-use and socket observation moved to daily records*, above, which superseded the accumulated-window form of this fix within the same release). **Counts move as a result — not-affected and open rise, undetermined falls — and that movement is a measurement change, not remediation**
- **Ephemeral UDP client sockets were accumulated as listening services** (`hostinfo.enableSocketObservation`). `ss` reports UDP sockets with no state, so each random port `systemd-timesyncd` bound to receive an NTP reply was recorded as a new listener in the cumulative set. On compute1-prod that was 23 of 32 recorded keys, growing by exactly one per sample — about 8,600 phantom sockets a month, enough to make the evidence annex unusable. UDP sockets inside the kernel's `ip_local_port_range` are now counted as client sockets instead, with the range read from the kernel and published alongside a per-sample count so nothing is silently dropped. With daily records each day starts from an empty set, so no purge is needed
- **Socket sample counts were inflated for dual-stack listeners** (`hostinfo.enableSocketObservation`). A service bound on both `0.0.0.0` and `[::]` is two sockets under one `port/proto/bindClass` key, and the sampler incremented the count once per socket, so such entries reported twice as many samples as were ever taken. Observed live on compute2-prod, where every dual-stack entry read `4` after two samples. The count is now incremented once per sample; addresses, units and users still accumulate from every socket sharing the key
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
- **Socket observation (`hostinfo.enableSocketObservation`)** — the in-use sampler also records listening sockets with their bind address, and the user each unit actually runs as, recorded in the same daily observation record
  - **Bind address is the point**: a service bound to `127.0.0.1` is unreachable from anywhere else whatever the security group says. `postgresql-17.10` is the joint-largest package on compute2-prod at 26 CVEs, and "nothing outside this machine can reach it" is a far stronger claim than "5432 is not in the firewall list". Neither the Nix configuration nor the AWS API can state which address a process bound to
  - `bindClass` is `loopback`/`wildcard`/`specific`, kept beside the raw address. `[::]` is wildcard rather than IPv6-only, since such a socket accepts IPv4 too unless `v6only` is set; `::ffff:127.0.0.1` is loopback, observed live from Neo4j, and classifying it as `specific` would forfeit the strongest available claim
  - **Negative claims must use the `observed` set across the period**, not the `current` snapshot: a socket observed once proves only that it was bound then, and a listener that binds briefly under load would be absent from most samples
  - `units.user` maps a unit to the **list** of users observed, because a unit whose main process is root and drops privileges in a child would lose the root fact if collapsed. Joined against in-use data it yields what neither document produces alone: *openssl-3.6.0 is executed by `quiqr-server.service`, which runs as root, in a process listening on all interfaces*
  - `AF_NETLINK` is granted to the sampler only when socket observation is enabled: `ss` queries `sock_diag` over netlink, and denying it would return nothing while exiting successfully — the same silent blindness as hiding `/proc`
- **In-use code sampling** — vulnerability findings can now be split by whether the affected package's code has actually been observed executing. A CVE against a package says only that the package is present; this answers whether it runs, which is the evidence needed to argue a finding is not exploitable.
  - **`hostinfo.enableInUseSampler`** (default `false`) — a timer samples `/proc/<pid>/maps`, `/proc/<pid>/exe` and `/proc/<pid>/cmdline` every `inUseSamplerIntervalSeconds` (default 300), recording into a daily observation record served under `observations/` over the hostinfo port. All three sources are required: `maps` + `exe` alone observed 62 store paths on a live host, 71 with `cmdline` included
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
