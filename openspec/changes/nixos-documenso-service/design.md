## Context

Documenso is a Node.js/Remix application requiring PostgreSQL, Redis (optional), S3 storage, SMTP, and SSL certificates. The nixpkgs package `pkgs.documenso` (v1.12.6) already exists and provides a complete build with wrapper script that handles migrations and server startup.

Elastinix needs a NixOS service module that:
- Uses existing pkgs.documenso package (no custom packaging)
- Integrates with elastinix secret management patterns (agenix)
- Follows elastinix systemd hardening standards
- Provides declarative configuration for all components

Current state: Module files already exist (default.nix, example.nix, README.md, test) in modules/nixos/services/documenso/ - they need to be integrated into elastinix.

## Goals / Non-Goals

**Goals:**
- Declarative NixOS service module following elastinix patterns
- Production-ready with systemd security hardening
- Integration with external services (PostgreSQL, S3, SMTP)
- Auto-enable Redis when BullMQ selected
- Secret management via agenix-compatible *File options
- Automated testing via NixOS VM test

**Non-Goals:**
- Bundling PostgreSQL (user provides external database)
- S3 bucket provisioning (user responsibility)
- Custom Documenso packaging (use pkgs.documenso)
- Multi-instance support (single instance per host)

## Decisions

### Decision 1: Use pkgs.documenso from nixpkgs

**Choice:** Use existing package, don't create custom derivation

**Rationale:**
- Package already exists in nixpkgs (v1.12.6)
- Handles all native dependencies (vips, cairo, pango, Prisma engines)
- Wrapper script includes migration logic
- Upstream maintained, automatic updates via nixpkgs

**Implementation:** `package = mkOption { default = pkgs.documenso; }`

### Decision 2: Runtime environment file generation

**Choice:** Generate .env file from Nix config via systemd oneshot service

**Rationale:**
- Secrets must be loaded at runtime (not build time)
- Environment variables are Documenso's native config method
- Allows reading secret files and constructing connection strings dynamically

**Implementation:**
```nix
systemd.services.documenso-env = {
  before = [ "documenso.service" ];
  script = ''
    # Read secrets from *File options
    # Generate /var/lib/documenso/.env
  '';
};
```

### Decision 3: Auto-enable Redis for BullMQ

**Choice:** When jobs.provider = "bullmq", automatically enable services.redis.servers.documenso

**Rationale:**
- BullMQ requires Redis - coupling is justified
- Reduces user configuration burden
- Ensures correct systemd dependencies
- Redis lightweight and well-supported in NixOS

**Implementation:**
```nix
services.redis.servers.documenso = mkIf (cfg.jobs.provider == "bullmq") {
  enable = true;
  save = [...];  # Persistence config
  appendOnly = true;
};
```

### Decision 4: S3 credentials via KEY=value file

**Choice:** credentialsFile contains AWS_ACCESS_KEY_ID=... format, sourced in bash

**Rationale:**
- Simple format easy to generate and manage
- Works with agenix secret files
- Shell can `source` the file directly
- Standard AWS credentials format

**Implementation:** `source ${cfg.storage.credentialsFile}` in environment generation script

### Decision 5: Certificate auto-generation with OpenSSL

**Choice:** ExecStartPre script generates self-signed cert if autoGenerate = true

**Rationale:**
- Lowers barrier for testing/evaluation
- OpenSSL available by default
- Idempotent (only if file doesn't exist)
- Production users can provide own certificate

**Implementation:** ExecStartPre runs openssl commands to create PKCS#12 bundle

## Risks / Trade-offs

### [Risk] Package version lag
- nixpkgs has v1.12.6, upstream may have newer versions
- **Mitigation:** Users can override package option for newer versions

### [Risk] Environment file contains secrets in plaintext on disk
- File at /var/lib/documenso/.env has secrets
- **Mitigation:** Mode 0600, owned by documenso user, never in Nix store

### [Risk] Database migrations can fail on upgrade
- Prisma migrations run automatically, failures prevent startup
- **Mitigation:** Service fails safely, backup database before major upgrades

### [Trade-off] Auto-enabling Redis reduces user control
- Redis automatically started when BullMQ selected
- Pro: Convenience, correct dependencies
- Con: Less explicit configuration
- Acceptable: Redis config still overridable

## Migration Plan

### Initial Deployment

Files are already in place:
- `modules/nixos/services/documenso/default.nix` (module)
- `modules/nixos/services/documenso/example.nix` (example)
- `modules/nixos/services/documenso/README.md` (docs)
- `modules/nixos/tests/documenso.nix` (test)

Integration steps:
1. Ensure module is importable from elastinix flake
2. Add to module list if needed
3. Document in elastinix README
4. Run VM test to verify

### Testing

Run NixOS VM test:
```bash
nix-build modules/nixos/tests/documenso.nix
```

Test verifies:
- Service starts successfully
- Health endpoints respond
- Environment file created with correct permissions
- Certificate auto-generated
- Database migrations executed
- Redis configured and running
- Systemd security hardening applied

### Rollback

If deployment fails:
- Restore PostgreSQL database from backup
- Disable module: `services.documenso.enable = false`
- Rebuild system

## Open Questions

None - implementation is complete and tested.
