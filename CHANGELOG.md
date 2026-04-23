# CHANGELOG

## Next version

### Added
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
