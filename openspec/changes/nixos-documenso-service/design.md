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
- Production users can provide own certificate via certificateFile
- Certificate can be encrypted with agenix for persistence across instances

**Implementation:** ExecStartPre runs openssl commands to create PKCS#12 bundle

### Decision 6: SMTP credentials via credentialsFile (alternative to username+passwordFile)

**Choice:** Support both separate (username + passwordFile) and combined (credentialsFile) credential methods

**Rationale:**
- Consistency with S3 credentialsFile pattern
- Simpler for AWS SES users (single encrypted file)
- Reduces number of secret files to manage
- Easier to rotate credentials atomically
- Still supports traditional separate approach for backward compatibility

**Implementation:**
```nix
# Method 1: Separate (original)
smtp = {
  username = "user";
  passwordFile = config.age.secrets.smtp-password.path;
};

# Method 2: Combined (new)
smtp = {
  credentialsFile = config.age.secrets.smtp-credentials.path;
};
```

File format: `SMTP_USERNAME=user\nSMTP_PASSWORD=pass`

**Validation:** Assertion prevents using both methods simultaneously

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

### [Risk] AWS SES SMTP configuration complexity
- Port 587 requires `secure = false` (STARTTLS), port 465 requires `secure = true` (direct TLS)
- AWS SES SMTP credentials are different from IAM access keys
- **Mitigation:** Comprehensive documentation with examples, troubleshooting guide for common errors

### [Trade-off] Stateless vs stateful certificate management
- autoGenerate = true: Stateless but new cert on each rebuild
- certificateFile via agenix: Persistent cert across instances, requires secret management
- Pro (stateless): Works with Auto Scaling, Spot instances, no EBS needed
- Con (stateless): Certificate changes on each instance recreation
- Acceptable: For production, use agenix-encrypted certificate for persistence

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

**Automated NixOS VM test:**
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

**Manual end-to-end validation (completed):**

Created standalone VM test environment (`/tmp/documenso-test/vm-config.nix`) that validated:

1. **S3 Integration:**
   - Document upload to real AWS S3 bucket
   - S3 CORS configuration for PDF viewing in browser
   - Presigned URL generation and access
   - IAM credential management via credentialsFile

2. **SMTP/Email Delivery:**
   - AWS SES SMTP integration (port 587 with STARTTLS)
   - SMTP credentialsFile authentication method
   - Email job queueing via BullMQ
   - Email delivery to recipients
   - Document distribution workflow

3. **Complete Signing Workflow:**
   - User authentication and session management
   - Document upload and metadata storage
   - Recipient configuration (multiple recipients)
   - Field placement (signature, date, text)
   - Document distribution via email
   - Signing completion and audit trail

4. **Edge Cases Validated:**
   - SMTP secure=false required for STARTTLS (port 587)
   - AWS SES requires SMTP credentials (not IAM keys)
   - S3 CORS must allow origin for PDF viewing
   - DocumentMeta.distributionMethod must be "EMAIL" for email sending
   - BullMQ jobs process asynchronously (not immediate)

**Configuration Patterns Tested:**
- External PostgreSQL (VM local for testing, RDS-ready)
- Redis auto-enablement with BullMQ
- Certificate auto-generation with passphraseFile
- All secrets via agenix-compatible file paths
- Stateless deployment (certificate via agenix, no persistent storage needed)

### Rollback

If deployment fails:
- Restore PostgreSQL database from backup
- Disable module: `services.documenso.enable = false`
- Rebuild system

## Open Questions

None - implementation is complete and extensively tested.

## Future Enhancements

**CloudWatch Logs Integration** (GitHub Issue #11):
- Optional CloudWatch Logs agent configuration
- Centralized log aggregation for multi-instance deployments
- Log retention policies
- Enables fully stateless EC2 deployments (no local log persistence needed)
- Complements existing stateless architecture (RDS + S3 + ElastiCache + agenix)

**Design considerations:**
- Use `pkgs.amazon-cloudwatch-agent`
- Configure via systemd service streaming journald logs
- Support EC2 instance profile IAM authentication
- Auto-create log groups (optional)
- Configurable retention periods
