## Why

NixOS users need a declarative service module to deploy Documenso (open-source DocuSign alternative) on their infrastructure. Currently, users must manually configure all components (database connections, Redis, S3, SMTP, certificates) which is error-prone and not reproducible. A proper NixOS service module integrates with elastinix's existing patterns for secret management, systemd hardening, and declarative configuration.

## What Changes

- Add NixOS service module `modules/nixos/services/documenso/default.nix`
- Add example configuration `modules/nixos/services/documenso/example.nix`
- Add complete documentation `modules/nixos/services/documenso/README.md`
- Add NixOS VM test `modules/nixos/tests/documenso.nix`
- Module exposes `services.documenso` configuration interface
- Supports external PostgreSQL database with automatic migration on startup
- Auto-enables Redis for BullMQ job provider (scheduled reminders)
- Integrates S3-compatible storage for PDF documents
- Configures SMTP for email notifications
- Manages PDF signing certificates (auto-generate or user-provided)
- All secrets via `*File` options (agenix/sops-nix compatible)
- Applies systemd security hardening

## Capabilities

### New Capabilities
- `nixos-service-module`: NixOS service module for Documenso with declarative configuration
- `database-integration`: External PostgreSQL connection with automatic Prisma migrations
- `redis-bullmq-integration`: Redis service auto-enablement for BullMQ job provider
- `s3-storage-config`: S3-compatible storage configuration with credential management
- `smtp-email-config`: SMTP server configuration for email delivery
- `certificate-management`: PDF signing certificate provisioning and auto-generation
- `secret-management`: Integration with agenix/sops-nix via file-based secrets
- `systemd-hardening`: Security hardening for Documenso systemd service
- `nixos-vm-testing`: Automated testing infrastructure for the module

### Modified Capabilities
<!-- No existing capabilities are being modified -->

## Impact

**New Files:**
- `modules/nixos/services/documenso/default.nix` - Main service module (500+ lines)
- `modules/nixos/services/documenso/example.nix` - Example configuration
- `modules/nixos/services/documenso/README.md` - Documentation
- `modules/nixos/tests/documenso.nix` - VM test suite

**Dependencies:**
- Uses `pkgs.documenso` from nixpkgs (v1.12.6)
- Requires external PostgreSQL database
- Optionally uses Redis (auto-enabled with BullMQ)
- Requires S3-compatible storage (AWS S3, MinIO, etc.)
- Requires SMTP server (Postfix, AWS SES, etc.)

**Integration Points:**
- Elastinix secret management patterns (agenix)
- Elastinix systemd hardening standards
- NixOS module conventions

**No Breaking Changes** - This is a new module addition
