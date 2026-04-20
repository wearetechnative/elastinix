# Documenso Service

Open-source document signing platform - the free DocuSign alternative.

## Overview

Documenso is a pure NixOS service module that deploys the Documenso document signing platform using `pkgs.documenso` from nixpkgs. Digital document signing with email notifications, scheduled reminders, and secure PDF certificates.

## Features

- **Pure NixOS** - Uses `pkgs.documenso` from nixpkgs, no Docker
- **External PostgreSQL** - Automatic Prisma migrations  
- **BullMQ jobs** - Redis-backed scheduled reminders
- **S3 storage** - S3-compatible object storage for PDFs
- **SMTP integration** - Email via SMTP (Postfix relay supported)
- **Certificate management** - Auto-generate or provide your own
- **agenix secrets** - Full agenix integration
- **Security hardening** - Systemd security directives

## Quick Start

See [example.nix](../../modules/nixos/services/documenso/example.nix) and [README](../../modules/nixos/services/documenso/README.md) for complete documentation.
