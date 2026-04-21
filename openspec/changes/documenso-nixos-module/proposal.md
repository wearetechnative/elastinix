## Why

Elastinix needs a production-ready NixOS module for Documenso (an open-source DocuSign alternative) to enable document signing capabilities for AWS-based NixOS deployments. Documenso requires complex integration with PostgreSQL, Redis, S3 storage, and SMTP services, making a declarative NixOS module essential for reliable and reproducible deployments.

## What Changes

- Add new `elastinix.services.documenso` NixOS module with comprehensive configuration options
- Support for external PostgreSQL database integration
- Automatic Redis service provisioning for BullMQ job queue
- S3-compatible storage configuration for document management
- SMTP integration for email notifications
- PDF signing certificate management (including auto-generation)
- Systemd service with proper startup sequencing and database migrations
- Secret management integration compatible with agenix and sops-nix
- Docker-based deployment using official Documenso image
- Optional reverse proxy configuration examples
- Health check and monitoring endpoints
- Complete documentation with deployment examples

## Capabilities

### New Capabilities
- `documenso-service`: Core NixOS module providing declarative configuration interface for Documenso deployment with database, storage, SMTP, and background job integration
- `redis-integration`: Automatic Redis service configuration for BullMQ job queue with persistence and security options
- `certificate-management`: PDF signing certificate management including auto-generation of self-signed certificates and secure passphrase handling
- `environment-generation`: Secure environment variable generation from declarative configuration with support for secret files
- `systemd-service`: Systemd service configuration with security hardening, proper dependency ordering, database migrations, and health checks

### Modified Capabilities
<!-- No existing capabilities are being modified -->

## Impact

**New Files:**
- `modules/nixos/services/service-documenso.nix` - Main service module
- `docs/services/documenso.md` - Service documentation
- `docs/examples/documenso/` - Example configurations (basic, production, agenix integration)

**Modified Files:**
- `docs/README.md` - Add documenso to services index
- `flake.nix` - Add documenso package input (if packaging required)

**Dependencies:**
- Documenso Docker image: `documenso/documenso:latest`
- Redis service (NixOS built-in)
- External PostgreSQL database (user-provided)
- External S3 storage (user-provided)
- External SMTP server (user-provided, typically Postfix with AWS SES relay)

**Infrastructure Impact:**
- New port usage: TCP 3000 (Documenso HTTP)
- New systemd service: `documenso.service`
- New Redis instance: `redis-documenso.service` (optional, when using BullMQ)
- Storage requirements: `/var/lib/documenso/` for application state
- Reverse proxy integration required for production HTTPS access
