# CHANGELOG

## Next version

### Added
- **Host Attack Surface Profile** (`elastinix.hasp`) — a static, content-hashed per-host fact document served by hostinfo as `hasp.json`, built from a closed fact registry that fails the build on an unregistered key, with optional live AWS fact collection (`awsFacts`) and socket observation (`hostinfo.enableSocketObservation`) recording each listener's bind address and the users its unit runs as ([docs](docs/services/hasp.md)).
- **In-use code sampling** (`hostinfo.enableInUseSampler`, default `false`) — a timer samples `/proc/<pid>/maps`, `/proc/<pid>/exe` and `/proc/<pid>/cmdline` to record which packages are actually observed executing and the systemd units holding them, surfaced as an `inuse` label on `vulnix_vulnerabilities_total` where absent, stale or gapped data resolves to `unknown` and never to `false` ([docs](docs/services/hostinfo.md)).

### Fixed
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
