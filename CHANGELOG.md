# CHANGELOG

## Next version

### Fixed
- **vulnix-scan bootstrap op t3.small**: service werkte niet op instances met weinig RAM (1.9GB, geen swap) — initiële NVD cache-opbouw werd afgebroken door OOM killer
  - Bootstrap-mechanisme: bij lege cache tijdelijk 1.5GB swapfile aanmaken, NVD database opbouwen (~2 min), swapfile verwijderen
  - Disk-check vooraf: minimaal 2GB vrij vereist; anders overgeslagen met waarschuwing
  - `ExecStopPost` ruimt swapfile op bij onverwacht afbreken
  - Cache verplaatst van `/var/lib/sbom/cache` naar `/var/lib/vulnix-cache` (scheiding verantwoordelijkheden)

### Changed
- **vulnix-scan packages.json**: service genereert packages.json niet meer zelf via `nix-store -qR`; leest `/var/lib/sbom/packages.json` dat door de deploy-wrapper aangeleverd wordt bij elke deployment

### Added
- **Grafana/Prometheus Cognito authentication**: `elastinix.services.grafana-prometheus.oauth2Proxy` puts Prometheus and Alertmanager behind an OIDC identity provider (AWS Cognito) via oauth2-proxy + nginx `auth_request`
  - Single sign-on across `prometheus.<domain>`, `alertmanager.<domain>` and the Grafana session
  - Group-based authorization via the OIDC groups claim (`groupsClaim`, `allowedGroups`)
  - OIDC client secret and cookie secret read from files via systemd credentials (`clientSecretFile`, `cookieSecretFile`)
  - Metrics endpoints bound to `127.0.0.1` and raw ports `9090 9100 9115 9109` dropped from the firewall (delivered in the `wearetechnative/monitoring` module)
  - New documentation at `docs/services/grafana-prometheus.md`
  - Requires bumping the `grafana-prometheus` flake input once the monitoring change is merged
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
