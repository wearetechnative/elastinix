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
- Configures SMTP for email notifications with two credential methods:
  - Individual: `username` + `passwordFile`
  - Combined: `credentialsFile` (KEY=value format, like S3)
- Manages PDF signing certificates (auto-generate or user-provided, agenix-compatible)
- All secrets via `*File` options (agenix/sops-nix compatible)
- Applies systemd security hardening
- Comprehensive troubleshooting documentation:
  - SMTP/email delivery issues (AWS SES, STARTTLS vs direct TLS)
  - S3 CORS configuration for PDF viewing
  - Certificate management
  - Redis/BullMQ job processing
  - Database connection issues
- AWS-specific documentation:
  - AWS SES SMTP configuration (port 587 vs 465)
  - S3 CORS policy examples
  - IAM permissions guidance
  - Stateless EC2 deployment patterns
- Multiple SMTP authentication examples in documentation

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
  - SMTP credentialsFile option with validation assertions
  - Environment file generator with credential sourcing
  - Certificate auto-generation with OpenSSL
  - Redis auto-enablement for BullMQ
- `modules/nixos/services/documenso/example.nix` - Example configuration
  - Three SMTP authentication examples (local relay, SES separate, SES combined)
  - agenix secret management examples
  - Production-ready configuration patterns
- `modules/nixos/services/documenso/README.md` - Comprehensive documentation
  - SMTP credential methods (username+passwordFile vs credentialsFile)
  - AWS SES configuration guide (port 587 vs 465, STARTTLS vs direct TLS)
  - Troubleshooting sections (SMTP, S3 CORS, email delivery, certificates)
  - IAM permissions for S3 and SES
  - Stateless EC2 deployment guidance
  - agenix secret generation examples
- `modules/nixos/tests/documenso.nix` - VM test suite (10 test cases)

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

## Testing & Validation

**End-to-End Testing:**
- Complete workflow tested on standalone NixOS VM
- Document upload to S3 with CORS validation
- Email delivery via AWS SES SMTP (STARTTLS on port 587)
- PDF signing with auto-generated certificates
- BullMQ job processing with Redis
- Multi-recipient document distribution
- Full signing workflow from upload to completion

**Production Scenarios Validated:**
- Stateless EC2 deployment (no persistent storage needed)
- External RDS PostgreSQL integration
- AWS S3 storage with CORS
- AWS SES SMTP integration
- Redis/ElastiCache for BullMQ
- agenix secret management for all credentials
- Certificate management via agenix (encrypted .p12 files)

**Edge Cases Documented:**
- SMTP authentication failures (SES credentials vs IAM keys)
- SSL/TLS configuration (STARTTLS vs direct TLS)
- S3 CORS blocking PDF viewing
- Email distribution method configuration (EMAIL vs NONE)
- BullMQ job queue monitoring

## Future Enhancements

**Planned (GitHub Issue #11):**
- Optional CloudWatch Logs integration for stateless EC2 deployments
- Centralized log aggregation
- Log retention policies
- Multi-instance log correlation

**Enables:**
- Fully stateless EC2 instances in Auto Scaling Groups
- Safe use of Spot instances
- Zero persistent storage requirements on EC2
- Complete AWS-native deployment pattern
