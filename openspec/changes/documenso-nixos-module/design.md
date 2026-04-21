## Context

Documenso is a Node.js/Remix application requiring orchestration of multiple services (PostgreSQL, Redis, S3, SMTP) with complex environment configuration. The official deployment method uses Docker containers, which aligns well with NixOS's OCI container support.

**Current State:**
- Elastinix has several service modules following established patterns (jirasync, systemd-monitoring, etc.)
- Services use `elastinix.services.<name>` namespace with multi-instance support via `instances` attrset
- External dependencies are managed via flake inputs with nixpkgs "follows" pattern
- Agenix is the primary secret management solution

**Constraints:**
- Must use official Documenso Docker image (avoid custom Node.js packaging complexity)
- External PostgreSQL database (not bundled)
- External S3 storage (not provisioned by module)
- Must support agenix without circular dependencies
- Must follow elastinix security hardening standards

## Goals / Non-Goals

**Goals:**
- Provide declarative NixOS configuration for production-ready Documenso deployments
- Support all required integrations (database, Redis, S3, SMTP, certificates)
- Enable secret management via agenix and sops-nix
- Automatic Redis provisioning when using BullMQ
- Automatic certificate generation for testing/development
- Systemd service with proper dependency ordering and migrations
- Clear documentation with multiple deployment examples

**Non-Goals:**
- Bundling PostgreSQL database (users provide external database)
- S3 bucket provisioning (users configure AWS separately)
- Multi-instance Documenso deployment (no horizontal scaling support)
- SSL/HTTPS termination (handled by reverse proxy like nginx/traefik)
- Native Node.js packaging (use Docker image for simplicity)
- Kubernetes or container orchestration
- Backup automation (user responsibility)

## Decisions

### 1. Docker Deployment vs Native Node.js

**Decision:** Use `virtualisation.oci-containers.containers` with official Docker image.

**Rationale:**
- Official Documenso image is well-maintained and tested
- Avoids complex Node.js v22 packaging with native dependencies (sharp, Prisma engines)
- Upstream handles build complexity and turbo builds
- Easier upgrades (just update image tag)
- Consistent with upstream's recommended deployment

**Alternatives Considered:**
- Native Node.js packaging: High maintenance burden, need to package all dependencies including native modules
- Custom derivation: Would require maintaining build process separately from upstream

### 2. Single-Instance vs Multi-Instance

**Decision:** Single-instance service (no `instances` attrset).

**Rationale:**
- Documenso requires session affinity and shared state (not horizontally scalable)
- Single certificate per deployment
- Single public URL per deployment
- Most users need only one Documenso instance per server
- Simplifies configuration and avoids unnecessary abstraction

**Note:** Users needing multiple instances can use separate NixOS machines or containers.

### 3. Redis Integration

**Decision:** Automatically enable and configure Redis when `jobs.provider = "bullmq"`.

**Rationale:**
- Redis is required for BullMQ but not for local job provider
- NixOS has good built-in Redis support (`services.redis.servers`)
- Automatic provisioning reduces user configuration burden
- Can use dedicated Redis instance: `redis-documenso.service`

**Configuration:**
```nix
services.redis.servers.documenso = mkIf (cfg.jobs.provider == "bullmq") {
  enable = true;
  port = cfg.jobs.redis.port;
  bind = "127.0.0.1";  # localhost only for security
  requirePass = optional secret handling;
  save = [ ... ];  # persistence for job queue durability
};
```

### 4. Certificate Management

**Decision:** Support three modes:
1. User-provided certificate file (production)
2. Auto-generated self-signed certificate (development/testing)
3. Certificate contents as base64 string (advanced)

**Rationale:**
- Production needs real certificates
- Development/testing benefits from auto-generation
- Base64 option supports secret management systems

**Implementation:**
- Use systemd `ExecStartPre` to generate certificate if missing and `autoGenerate = true`
- Use OpenSSL commands for self-signed cert generation
- Store in `/var/lib/documenso/cert.p12` by default

### 5. Environment Variable Generation

**Decision:** Generate `/var/lib/documenso/.env` file from declarative config + secret files.

**Rationale:**
- Documenso expects environment variables
- Secrets must stay outside Nix store
- EnvironmentFile supports runtime secret loading
- Template approach keeps config declarative

**Implementation:**
- Build environment template in Nix with non-secret values
- Use systemd `LoadCredential` or `EnvironmentFile` for secrets
- Merge secrets from files (database password, API keys, etc.)

### 6. Database Migrations

**Decision:** Run `npx prisma migrate deploy` in `ExecStartPre` before starting service.

**Rationale:**
- Migrations must run before app starts
- Documenso includes migration scripts
- Automatic on every service start (idempotent)
- Prevents version mismatch errors

**Risk Mitigation:**
- Use `RemainAfterExit=false` to ensure migrations complete
- Add timeout for migration step
- Log migration output to journald

### 7. Secret Management

**Decision:** Use `*File` options for all secrets, compatible with agenix/sops-nix.

**Rationale:**
- Follows NixOS best practices
- Works with multiple secret management solutions
- Secrets never enter Nix store
- Users can reference `config.age.secrets.<name>.path`

**Pattern:**
```nix
services.documenso = {
  database.passwordFile = config.age.secrets.documenso-db-password.path;
  secrets.nextAuthSecretFile = config.age.secrets.documenso-nextauth.path;
  # etc.
};
```

**Avoiding Circular Dependencies:**
- Hardcode agenix secret owner/group as `documenso` (service user)
- Don't reference `cfg.user` in age secrets configuration
- Document pattern in service documentation

### 8. Systemd Security Hardening

**Decision:** Apply standard elastinix security hardening with Docker-specific adjustments.

**Settings:**
```nix
{
  # Standard hardening
  NoNewPrivileges = true;
  PrivateTmp = true;
  ProtectSystem = "strict";
  ProtectHome = true;

  # Docker-specific
  ReadWritePaths = [ "/var/lib/documenso" ];

  # Network
  RestrictAddressFamilies = [ "AF_INET" "AF_INET6" ];

  # Capabilities (Docker may need some)
  CapabilityBoundingSet = [ "CAP_NET_BIND_SERVICE" ];
}
```

### 9. Flake Input for Documenso

**Decision:** Don't add flake input; use Docker image directly via `dockerTools`.

**Rationale:**
- Docker image is the canonical distribution
- No need for separate flake dependency
- Image tag can be configured by users
- Simpler dependency tree

**Configuration:**
```nix
services.documenso = {
  image = "documenso/documenso:latest";  # User-configurable
};
```

## Risks / Trade-offs

### 1. Docker Dependency
**Risk:** Requires Docker/Podman on NixOS, adds container runtime overhead.
**Mitigation:** OCI containers are well-supported in NixOS, minimal overhead for single container.

### 2. Migration Failures
**Risk:** Database migrations could fail on startup, preventing service start.
**Mitigation:**
- Log migration output to journald
- Add timeout to migration step
- Users must test migrations in staging
- Document rollback procedure

### 3. Certificate Auto-Generation Security
**Risk:** Self-signed certificates in production are insecure.
**Mitigation:**
- Clearly document auto-generation is for development only
- Warn in logs when using auto-generated certificate
- Require explicit `autoGenerate = true` opt-in

### 4. Redis Single Point of Failure
**Risk:** Redis failure stops job processing (reminders, notifications).
**Mitigation:**
- Enable Redis persistence (AOF or RDB)
- Configure Redis to restart on failure
- Document Redis backup recommendations

### 5. S3 Credentials Exposure
**Risk:** S3 credentials in environment could be exposed via process inspection.
**Mitigation:**
- Use systemd `LoadCredential` for sensitive vars
- Set restrictive file permissions on .env file
- Recommend IAM roles over static credentials where possible

### 6. Upgrade Path Complexity
**Risk:** Documenso updates may require manual intervention or breaking changes.
**Mitigation:**
- Document upgrade testing process
- Recommend staging environment for testing
- Users control image tag explicitly
- Include changelog review in upgrade docs

### 7. No Multi-Instance Support
**Risk:** Users needing horizontal scaling can't use this module directly.
**Trade-off:** Accepted limitation - Documenso architecture doesn't support it well anyway (session affinity required).
**Alternative:** Users needing HA should use container orchestration or multiple separate deployments with load balancer.

## Migration Plan

**Initial Deployment:**
1. User configures external PostgreSQL database
2. User configures S3 bucket and credentials
3. User adds module to NixOS configuration
4. `nixos-rebuild switch`
5. Service starts, runs migrations, becomes available

**No Migration from Existing Systems:**
- This is a new module, no migration from old deployments needed
- Users migrating from Docker Compose should export PostgreSQL data and import to external database

**Rollback Strategy:**
- Remove or disable module configuration
- `nixos-rebuild switch` to previous generation
- Database remains intact (external)
- S3 documents remain intact (external)

**Testing Strategy:**
1. Test basic deployment with local PostgreSQL (for development)
2. Test with external PostgreSQL (production scenario)
3. Test BullMQ vs local job provider
4. Test certificate auto-generation
5. Test secret management with agenix
6. Test upgrade by changing Docker image version
7. Test service restart and migration behavior

## Open Questions

**None at this time.**

All major design decisions have been made based on the requirements document. Implementation can proceed with the specs and tasks phases.
