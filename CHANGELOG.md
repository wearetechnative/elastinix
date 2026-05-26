# CHANGELOG

## Next version

### Added
- **Jira Ticket Create service**: Scheduled Jira ticket creation per client and check type
  - Define reusable check types once (frequency, title template, description, issue type, due date offset)
  - Apply check types to multiple clients; generates one systemd timer+service per client×check combination
  - Supported frequencies: first working day of month, quarter, or week
  - `{period}` placeholder in title templates replaced at runtime (e.g. `2026-Q2`)
  - Per-client Jira URL/user overrides for multi-instance setups
  - Jira API token via agenix secret per client
  - Standard elastinix systemd hardening applied to all generated services
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
