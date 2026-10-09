# CHANGELOG

## Next version

### Added
- **`bootstrapNixpkgs` argument for `tf_command`** (default `nixpkgs`): the bootstrap AMI is built from this nixpkgs instead of the live system's. Pinning it keeps the AMI, and with it the EC2 instance, unchanged when `nixpkgs` is updated; a kernel update then only needs a reboot ([README](README.md#pinning-the-bootstrap-image))
- **Attic pull consumer** (`elastinix.services.attic_pull`): makes a host pull from a private Attic cache. It replaces the per-repository module in the workloads stacks, and it has no knowledge of tfvars ([docs](docs/services/attic-pull.md))
  - Sets the three Nix settings that have to change together: the substituter `<endpoint>/<cache>` and its trusted key, both appended with `mkAfter` so `cache.nixos.org` stays first, and `netrc-file` pointing at the pull credential
  - `netrc_file` is a path string, so the secret never enters the Nix store and the module doesn't depend on agenix; the docs show the matching agenix secret (`owner = "root"`, `mode = "400"`)
  - Refuses at evaluation time a missing value, an endpoint without scheme, an invalid Attic cache name, a malformed public key, a relative netrc path, and a pasted 64-byte **secret** key, which it names as such
  - New checks `attic-pull` (evaluation) and `attic-pull-vm` (two-node VM: a client can't substitute from a private cache without its netrc, and can with it)
- **Attic garbage collection and retention** (`elastinix.services.attic.garbage_collection`) — the module renders a `[garbage-collection]` section instead of inheriting attic's defaults invisibly, with `interval` stated explicitly at its upstream 12 hours and `default_retention_period` defaulting to **90 days**; `null` renders `"0"`, attic's own encoding for time-based collection off ([docs](docs/services/attic.md))
  - Before this the cache was append-only. Attic's collector was never idle — it reaps orphans on every pass regardless of retention — but an object row keeps its NAR referenced forever, so a closure nobody pulls any more never becomes an orphan and never left
  - "90 days" means old **and** unused: deletion requires both `created_at` and `last_accessed_at` to precede the cutoff, and only downloading the NAR bumps the latter, never a `.narinfo` lookup
- **Attic log filter** (`elastinix.services.attic.log_filter`, default `attic_server=info`) — atticd builds its subscriber with `EnvFilter::from_default_env()`, so without `RUST_LOG` everything below `error` is discarded and the garbage collector runs completely silently; its startup lines are `eprintln!` and appear regardless, which made the service look more talkative than its log level allowed
- **Host Attack Surface Profile** (`elastinix.hasp`) — a static, content-hashed per-host fact document served by hostinfo as `hasp.json`, built from a closed fact registry that fails the build on an unregistered key, with optional live AWS fact collection (`awsFacts`) and socket observation (`hostinfo.enableSocketObservation`) recording each listener's bind address and the users its unit runs as ([docs](docs/services/hasp.md)).
- **In-use code sampling** (`hostinfo.enableInUseSampler`, default `false`) — a timer samples `/proc/<pid>/maps`, `/proc/<pid>/exe` and `/proc/<pid>/cmdline` to record which packages are actually observed executing and the systemd units holding them, surfaced as an `inuse` label on `vulnix_vulnerabilities_total` where absent, stale or gapped data resolves to `unknown` and never to `false` ([docs](docs/services/hostinfo.md)).
- **Badgersbay health checks** — the module declares `healthchecks.http.badgersbay` and `healthchecks.localCommands.badgersbay-storage`, so what healthy means for this service lives with the service instead of being invented per host
  - The checks address the unauthenticated `/health` endpoint on the loopback at `port`, never the dashboard at `/`, which is behind basic auth and answers 401 in every state — healthy or not — while filling the log
  - The second check parses the response because the first cannot cover it: the server answers 200 with `storage.accessible` false when the directory it writes submissions to has gone, and a status code alone would call that healthy
  - They are definitions, not units: no process, no timer, nothing that runs on its own. They are run from the host flake that defines the machine (`nix run .#healthchecks`), and a monitoring probe belongs in the probes file, pointed at `/health` ([docs](docs/services/badgersbay.md))
- **Evidence bundle export** (`vulnerability-scan-central`) — each scan run is normalized into one schema-versioned `evidence.json`, optionally uploaded write-only to versioned S3 so the history is tamper-evident, letting an ISO 27001 report be generated from a single immutable snapshot without live access to hosts or AWS ([docs](docs/services/vulnerability-scan-central.md)).

### Changed
- **Badgersbay no longer declares an hourly timer**: `systemd.timers.badgersbay` fired `OnCalendar=hourly` at a `Type=simple` daemon that is already running, where starting an active service is a no-op — it was a workaround for the configuration never being re-read (now handled by `restartTriggers`) and it never once had that effect
  - One behaviour is removed with it: a badgersbay that exhausted systemd's start limit was started again by the next hourly firing, and now stays `failed` until a deploy or a manual start. Deliberate — this service's failures are not the kind that waiting fixes — so list it in `elastinix.services.systemd-monitoring.services` if nothing else watches it ([docs](docs/services/badgersbay.md))
- **Observation moved to sealed daily records** written where they are served (`/var/lib/hostinfo/observations/`), replacing the forever-growing in-use document so a negative claim is bounded by the monthly reporting period rather than by whatever had elapsed since the last deploy; the scan timer now defaults to `daily`, the existing cumulative evidence is discarded so every host reports `inUse: "unknown"` for one day, and migration on a deployed host is manual and order-critical ([docs](docs/services/hostinfo.md)).

### Fixed
- **Attic takes its database from the environment file** (`elastinix.services.attic.database_url`, default `null`) — the generated `checked-attic-server.toml` no longer carries the upstream SQLite `database.url`, so atticd uses `ATTIC_SERVER_DATABASE_URL` from the agenix environment file, as the hosts always intended, instead of an empty SQLite file on the root volume that was lost with every instance replacement ([docs](docs/services/attic.md))
  - The database holds every cache's signing keypair; the S3 bucket only holds chunks. The database therefore decides whether a cache survives, and it now lives in the shared, backed-up PostgreSQL
  - **Breaking**: without `ATTIC_SERVER_DATABASE_URL` atticd now fails to start instead of silently running on SQLite. SQLite stays available as an explicit `database_url`, which is also the rollback
  - A `database_url` containing a password is refused at evaluation time, because the generated configuration is world-readable in `/nix/store`
  - New NixOS VM test `checks.<linux-system>.attic-database`: atticd on PostgreSQL via the environment file, fail-loud without it, and a cache whose public key is unchanged after the local state directory is wiped
- **Badgersbay now restarts when its secrets change**: the module declares `restartTriggers` on the configuration, the API tokens, the dashboard password and the asset register, so a deploy that changes one of them reaches the running process instead of landing on disk while the service keeps serving what it read at its last start — a rotated token that still accepts the old one, or a reissued asset register measured against the previous one, neither of which reported anything
  - An agenix secret arrives at a stable path, so the trigger is the `.age` source it is decrypted from; re-encrypting a secret is therefore enough to restart the service, even with no edit
  - A secret that is neither in the nix store nor declared to agenix is still not covered — nothing about it is readable at evaluation ([docs](docs/services/badgersbay.md))
- **CVE overcounting in vulnerability reports**: multi-output deduplication (`deduplicateOutputs`) and CPE vendor exclusion (`cveVendorExclusions`, fed by the local `patches/vulnix-emit-cpe-vendors.patch`) drop `vulnix_vulnerabilities_total` by ~44% with no change in scan coverage — a counting-accuracy fix rather than remediation, so re-baseline dashboards and alert thresholds and use the new `vulnix_distinct_cves_total` gauge for audit evidence.
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

- **Grafana/Prometheus Cognito authentication**: `elastinix.services.grafana-prometheus.oauth2Proxy` puts Prometheus and Alertmanager behind an OIDC identity provider (AWS Cognito) via oauth2-proxy + nginx `auth_request`
  - Single sign-on across `prometheus.<domain>`, `alertmanager.<domain>` and the Grafana session
  - Group-based authorization via the OIDC groups claim (`groupsClaim`, `allowedGroups`)
  - OIDC client secret and cookie secret read from files via systemd credentials (`clientSecretFile`, `cookieSecretFile`)
  - Metrics endpoints bound to `127.0.0.1` and raw ports `9090 9100 9115 9109` dropped from the firewall (delivered in the `wearetechnative/monitoring` module)
  - New documentation at `docs/services/grafana-prometheus.md`

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
