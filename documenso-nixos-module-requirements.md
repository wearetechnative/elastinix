# Documenso NixOS Module - Requirements Document

## Project Overview

Implement a production-ready NixOS module for deploying Documenso (open-source DocuSign alternative) with external PostgreSQL, Redis-backed background jobs, and S3 storage.

## Context

Documenso is a Node.js/Remix application that requires:
- PostgreSQL database (external)
- SMTP server for email notifications
- Document storage (S3-compatible)
- Background job processing (Redis/BullMQ for scheduled reminders)
- SSL certificate for PDF signing
- Reverse proxy with SSL termination

Current state:
- Repository: https://github.com/documenso/documenso
- Docker image available: `documenso/documenso:latest`
- Development environment uses Docker Compose
- Production deployment needs proper NixOS integration

## Architecture

```
┌──────────────────────────────────────────────────────────────┐
│                    Production Architecture                    │
└──────────────────────────────────────────────────────────────┘

              ┌───────────────────────┐
              │   Nginx/Traefik       │
              │   (SSL Termination)   │
              │   HTTPS → HTTP:3000   │
              └───────────┬───────────┘
                          │
              ┌───────────▼────────────┐
              │   Documenso App        │
              │   Node.js/Remix        │
              │   Port: 3000           │
              └───┬────────┬───────┬───┘
                  │        │       │
      ┌───────────┘        │       └──────────────┐
      │                    │                      │
┌─────▼──────┐    ┌───────▼────────┐    ┌────────▼────────┐
│PostgreSQL  │    │ Redis (local)  │    │ S3 Storage      │
│(External)  │    │ BullMQ Jobs    │    │ (PDFs)          │
└────────────┘    └────────────────┘    └─────────────────┘
      ▲
      │ Postfix (SMTP)
      │ relay: smtp-aws
```

## Requirements

### 1. NixOS Module Configuration

The module should provide a declarative configuration interface:

```nix
services.documenso = {
  enable = true;

  # Public URL
  publicUrl = "https://documenso.example.com";

  # Database configuration
  database = {
    host = "postgres.internal.example.com";
    port = 5432;
    name = "documenso";
    user = "documenso";
    passwordFile = "/run/secrets/documenso-db-password";
  };

  # SMTP configuration
  smtp = {
    host = "localhost";  # Postfix with AWS SES relay
    port = 25;
    fromAddress = "noreply@example.com";
    fromName = "Document Signing";
    # Optional: username, password, secure, etc.
  };

  # Storage configuration
  storage = {
    type = "s3";
    bucket = "documenso-documents";
    endpoint = "s3.amazonaws.com";  # or MinIO endpoint
    region = "eu-west-1";
    credentialsFile = "/run/secrets/s3-credentials";  # AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY
  };

  # Background jobs
  jobs = {
    provider = "bullmq";  # or "local" for PostgreSQL-based
    redis = {
      host = "127.0.0.1";
      port = 6379;
      # Optional: passwordFile, prefix
    };
  };

  # PDF signing certificate
  signing = {
    passphraseFile = "/run/secrets/documenso-signing-passphrase";
    certificateFile = "/opt/documenso/cert.p12";
    # OR: certificateContents for base64-encoded cert
  };

  # Security
  secrets = {
    nextAuthSecretFile = "/run/secrets/documenso-nextauth";
    encryptionKeyFile = "/run/secrets/documenso-encryption-key";
    encryptionSecondaryKeyFile = "/run/secrets/documenso-encryption-secondary-key";
  };

  # Optional features
  features = {
    disableSignup = false;
    allowedSignupDomains = [ "example.com" ];
    disableTelemetry = true;
  };

  # Optional OAuth providers
  oauth = {
    google = {
      clientId = "...";
      clientSecretFile = "/run/secrets/google-oauth-secret";
    };
  };
};
```

### 2. Required Services Integration

#### Redis Service
- Automatically enable Redis when `jobs.provider = "bullmq"`
- Use `services.redis.servers.documenso`
- Configure persistence for job queue durability
- Optional: password protection

#### Systemd Service
- Service name: `documenso.service`
- User: `documenso` (dedicated, non-root)
- Working directory: `/var/lib/documenso`
- Environment file: `/var/lib/documenso/.env` (generated from config)
- Startup sequence:
  1. Wait for PostgreSQL and Redis
  2. Run database migrations (`npx prisma migrate deploy`)
  3. Start application server

#### Nginx/Traefik Reverse Proxy
- Optional reverse proxy configuration
- SSL termination
- WebSocket support (if needed)
- Proxy headers (X-Forwarded-For, etc.)

### 3. Environment Variables Mapping

The module must generate these environment variables:

**Required:**
```bash
# Auth & Crypto
NEXTAUTH_SECRET=<from secrets.nextAuthSecretFile>
NEXT_PRIVATE_ENCRYPTION_KEY=<from secrets.encryptionKeyFile>
NEXT_PRIVATE_ENCRYPTION_SECONDARY_KEY=<from secrets.encryptionSecondaryKeyFile>

# URLs
NEXT_PUBLIC_WEBAPP_URL=<from publicUrl>
NEXT_PRIVATE_INTERNAL_WEBAPP_URL="http://127.0.0.1:3000"

# Database (no connection pooler)
NEXT_PRIVATE_DATABASE_URL="postgresql://<user>:<password>@<host>:<port>/<name>"
NEXT_PRIVATE_DIRECT_DATABASE_URL="<same as above>"

# SMTP
NEXT_PRIVATE_SMTP_TRANSPORT="smtp-auth"
NEXT_PRIVATE_SMTP_HOST=<from smtp.host>
NEXT_PRIVATE_SMTP_PORT=<from smtp.port>
NEXT_PRIVATE_SMTP_FROM_NAME=<from smtp.fromName>
NEXT_PRIVATE_SMTP_FROM_ADDRESS=<from smtp.fromAddress>

# Storage (S3)
NEXT_PUBLIC_UPLOAD_TRANSPORT="s3"
NEXT_PRIVATE_UPLOAD_ENDPOINT=<from storage.endpoint>
NEXT_PRIVATE_UPLOAD_REGION=<from storage.region>
NEXT_PRIVATE_UPLOAD_BUCKET=<from storage.bucket>
NEXT_PRIVATE_UPLOAD_ACCESS_KEY_ID=<from storage.credentialsFile>
NEXT_PRIVATE_UPLOAD_SECRET_ACCESS_KEY=<from storage.credentialsFile>

# Background Jobs (BullMQ)
NEXT_PRIVATE_JOBS_PROVIDER="bullmq"
NEXT_PRIVATE_REDIS_URL="redis://<host>:<port>"
NEXT_PRIVATE_REDIS_PREFIX="documenso"

# Signing
NEXT_PRIVATE_SIGNING_PASSPHRASE=<from signing.passphraseFile>
NEXT_PRIVATE_SIGNING_LOCAL_FILE_PATH=<from signing.certificateFile>
```

**Optional:**
```bash
# Features
NEXT_PUBLIC_DISABLE_SIGNUP=<from features.disableSignup>
NEXT_PRIVATE_ALLOWED_SIGNUP_DOMAINS=<comma-separated from features.allowedSignupDomains>
DOCUMENSO_DISABLE_TELEMETRY=<from features.disableTelemetry>

# OAuth (if configured)
NEXT_PRIVATE_GOOGLE_CLIENT_ID=<from oauth.google.clientId>
NEXT_PRIVATE_GOOGLE_CLIENT_SECRET=<from oauth.google.clientSecretFile>
```

### 4. Deployment Method

**Option: Docker via NixOS (Recommended)**

Use `virtualisation.oci-containers.containers` with:
- Image: `documenso/documenso:latest`
- Network: bridge or host
- Volumes:
  - Certificate mount: `${signing.certificateFile}:/opt/documenso/cert.p12:ro`
  - Persistent data: `/var/lib/documenso:/app/data`
- Environment variables from generated .env file
- Health check: `curl http://localhost:3000/api/health`

**Alternative: Native Node.js Deployment**

If Docker is not desired:
- Build step: `npm run build` (turbo build)
- Binary: `node apps/remix/build/server/main.js`
- Requires: Node.js v22, Prisma engines, native dependencies (sharp, etc.)

### 5. Startup & Health Checks

**Startup Script** (from `docker/start.sh`):
```bash
#!/bin/sh
printf "🗄️  Running database migrations...\n"
npx prisma migrate deploy --schema ../../packages/prisma/schema.prisma

printf "🌟 Starting Documenso server...\n"
HOSTNAME=0.0.0.0 node build/server/main.js
```

**Health Check Endpoints:**
- `/api/health` - Overall health (database + certificate)
  - Returns: `{"status": "ok"}` or `{"status": "error"}`
- `/api/certificate-status` - Certificate signing status

**Systemd Service Configuration:**
```ini
[Unit]
Description=Documenso Document Signing Service
After=network.target postgresql.service redis-documenso.service
Requires=redis-documenso.service

[Service]
Type=simple
User=documenso
Group=documenso
WorkingDirectory=/var/lib/documenso
EnvironmentFile=/var/lib/documenso/.env
ExecStartPre=/path/to/migrate-script.sh
ExecStart=/path/to/start-server.sh
Restart=always
RestartSec=10

# Security hardening
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=/var/lib/documenso

[Install]
WantedBy=multi-user.target
```

### 6. Certificate Management

**Self-signed Certificate Generation:**

The module should optionally generate a self-signed certificate if none is provided:

```bash
# Generate private key and certificate
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout /tmp/private.key \
  -out /tmp/certificate.crt \
  -subj '/C=NL/ST=Province/L=City/O=Organization/CN=documenso.example.com'

# Create PKCS#12 bundle
openssl pkcs12 -export -out /opt/documenso/cert.p12 \
  -inkey /tmp/private.key -in /tmp/certificate.crt \
  -passout pass:$SIGNING_PASSPHRASE

# Cleanup
rm /tmp/private.key /tmp/certificate.crt
```

Configuration option:
```nix
services.documenso.signing = {
  autoGenerate = true;  # Generate self-signed cert if certificateFile doesn't exist
  passphraseFile = "/run/secrets/documenso-signing-passphrase";
  certificateFile = "/var/lib/documenso/cert.p12";
};
```

### 7. Secret Management Integration

The module should work well with common secret management solutions:

- **agenix**: Support `age.secrets.*` references
- **sops-nix**: Support `sops.secrets.*` references
- **Plain files**: Support absolute paths to secret files

Example with agenix:
```nix
age.secrets = {
  documenso-db-password.file = ./secrets/db-password.age;
  documenso-nextauth.file = ./secrets/nextauth.age;
  documenso-encryption-key.file = ./secrets/encryption-key.age;
  # ... etc
};

services.documenso = {
  enable = true;
  database.passwordFile = config.age.secrets.documenso-db-password.path;
  secrets.nextAuthSecretFile = config.age.secrets.documenso-nextauth.path;
  # ... etc
};
```

### 8. Logging & Monitoring

**Logging:**
- Stdout/stderr to journald (systemd-journald)
- Optional: Log file output via `NEXT_PRIVATE_LOGGER_FILE_PATH`

**Monitoring:**
- Health check endpoint: `/api/health`
- Certificate status endpoint: `/api/certificate-status`
- Redis monitoring (if using BullMQ)
- Optional: Prometheus metrics (not built-in, may need custom exporter)

### 9. Backup Considerations

**What to backup:**
- PostgreSQL database (handled externally)
- S3 storage (handled externally)
- Certificate file (`/opt/documenso/cert.p12`)
- Environment secrets

**What NOT to backup:**
- Application code (reproducible via Nix)
- Redis data (transient job queue)
- Node modules

### 10. Upgrade Path

The module should support easy upgrades:

```nix
services.documenso = {
  enable = true;
  package = pkgs.documenso;  # or override with specific version
  # ... rest of config ...
};
```

Upgrade process:
1. Update `package` attribute (or nixpkgs)
2. Rebuild system
3. Systemd restarts service
4. Migrations run automatically on startup

## Technical Specifications

### Dependencies

- **Node.js**: v22 (required by Documenso)
- **PostgreSQL**: v14+ (external, user-provided)
- **Redis**: v6.2+ (local, managed by module)
- **OpenSSL**: For certificate generation
- **Docker** (if using container deployment): Podman or Docker

### Ports

- **3000**: Documenso application (HTTP)
- **6379**: Redis (localhost only)

### File Locations

- `/var/lib/documenso/`: Application state directory
- `/var/lib/documenso/.env`: Generated environment file
- `/opt/documenso/cert.p12`: Signing certificate (or custom path)
- `/var/log/documenso/`: Application logs (optional)

## Non-Functional Requirements

### Security
- Run as non-root user (`documenso`)
- Systemd hardening (NoNewPrivileges, PrivateTmp, etc.)
- Secrets in separate files (not in Nix store)
- Certificate file permissions: 0400 (read-only for documenso user)

### Performance
- BullMQ for job processing (better than PostgreSQL polling)
- Redis persistence for job queue durability
- S3 storage for scalable PDF storage

### Reliability
- Automatic service restart on failure
- Database migrations on startup
- Health checks for monitoring
- Proper dependency ordering (PostgreSQL → Redis → Documenso)

### Maintainability
- Declarative configuration (pure Nix)
- Easy upgrades via nixpkgs
- Clear logging to journald
- Standard NixOS patterns

## Testing Checklist

- [ ] Service starts successfully
- [ ] Database migrations run on first start
- [ ] Health endpoint returns 200 OK
- [ ] Can create user account
- [ ] Can upload and sign PDF document
- [ ] Email notifications sent via Postfix/SMTP
- [ ] PDFs stored in S3
- [ ] Background jobs processed via Redis/BullMQ
- [ ] Service restarts on failure
- [ ] Certificate signing works
- [ ] Reverse proxy (nginx/traefik) integration works
- [ ] Secrets loaded correctly from files
- [ ] Service runs as non-root user
- [ ] Logs available in journalctl

## References

- **Documenso Repository**: https://github.com/documenso/documenso
- **Docker README**: `docker/README.md` in repo
- **Environment Variables**: `.env.example` in repo
- **Docker Image**: https://hub.docker.com/r/documenso/documenso
- **Documentation**: https://docs.documenso.com

## Out of Scope

- Kubernetes/k8s deployment
- Multi-instance horizontal scaling (requires session affinity)
- Bundling PostgreSQL (use external database)
- S3 bucket provisioning (user responsibility)
- SSL certificate provisioning for HTTPS (use nginx/traefik)
- Backup automation (user responsibility)
- Monitoring/alerting setup (user adds Prometheus/Grafana)

## Success Criteria

A successful implementation allows a NixOS administrator to:

1. Add the module to their configuration
2. Configure database, SMTP, S3, and secrets
3. Enable the service with `services.documenso.enable = true`
4. Rebuild the system
5. Access a working Documenso instance at the configured URL
6. Sign documents with automatic email notifications and reminders
7. Upgrade Documenso by updating nixpkgs and rebuilding
8. Manage the service with standard systemctl commands

The module should follow NixOS best practices and integrate seamlessly with existing NixOS infrastructure.
