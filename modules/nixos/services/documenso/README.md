# Documenso NixOS Module

Pure NixOS service module for deploying [Documenso](https://github.com/documenso/documenso) - the open-source DocuSign alternative.

## Features

- ✅ Pure NixOS (no Docker required)
- ✅ Uses existing `pkgs.documenso` package
- ✅ Automatic database migrations on startup
- ✅ BullMQ/Redis support for scheduled reminders
- ✅ S3-compatible storage for PDFs
- ✅ Secret management integration (agenix, sops-nix)
- ✅ Auto-generate self-signed certificates
- ✅ Systemd security hardening
- ✅ Full declarative configuration

## Quick Start

### 1. Generate Secrets

```bash
# Database password
openssl rand -base64 32 > db-password.txt

# NextAuth secret (32+ characters)
openssl rand -hex 32 > nextauth-secret.txt

# Encryption keys (32+ characters each)
openssl rand -hex 32 > encryption-key.txt
openssl rand -hex 32 > encryption-secondary-key.txt

# Certificate passphrase
openssl rand -base64 24 > cert-passphrase.txt

# S3 credentials (create file with AWS keys)
cat > s3-credentials.txt <<EOF
AWS_ACCESS_KEY_ID=your_access_key_here
AWS_SECRET_ACCESS_KEY=your_secret_key_here
EOF
```

### 2. Encrypt Secrets with agenix

```bash
# Create secrets directory
mkdir -p secrets

# Encrypt each secret
agenix -e secrets/db-password.age < db-password.txt
agenix -e secrets/nextauth.age < nextauth-secret.txt
agenix -e secrets/encryption-key.age < encryption-key.txt
agenix -e secrets/encryption-secondary-key.age < encryption-secondary-key.txt
agenix -e secrets/cert-passphrase.age < cert-passphrase.txt
agenix -e secrets/s3-credentials.age < s3-credentials.txt

# Clean up plaintext files
shred -u *.txt
```

### 3. Configure NixOS

Add to your `configuration.nix`:

```nix
{ config, ... }:

{
  imports = [
    ./nixos-module.nix  # Path to the module
  ];

  age.secrets = {
    documenso-db-password.file = ./secrets/db-password.age;
    documenso-nextauth.file = ./secrets/nextauth.age;
    documenso-encryption-key.file = ./secrets/encryption-key.age;
    documenso-encryption-secondary-key.file = ./secrets/encryption-secondary-key.age;
    documenso-cert-passphrase.file = ./secrets/cert-passphrase.age;
    documenso-s3-credentials.file = ./secrets/s3-credentials.age;
  };

  services.documenso = {
    enable = true;
    publicUrl = "https://documenso.example.com";

    database = {
      host = "postgres.internal";
      passwordFile = config.age.secrets.documenso-db-password.path;
    };

    smtp = {
      host = "localhost";
      port = 25;
      fromAddress = "noreply@example.com";
    };

    storage = {
      type = "s3";
      bucket = "my-documenso-docs";
      region = "eu-west-1";
      credentialsFile = config.age.secrets.documenso-s3-credentials.path;
    };

    jobs.provider = "bullmq";

    secrets = {
      nextAuthSecretFile = config.age.secrets.documenso-nextauth.path;
      encryptionKeyFile = config.age.secrets.documenso-encryption-key.path;
      encryptionSecondaryKeyFile = config.age.secrets.documenso-encryption-secondary-key.path;
    };

    signing = {
      autoGenerate = true;
      passphraseFile = config.age.secrets.documenso-cert-passphrase.path;
    };
  };

  # Reverse proxy
  services.nginx.virtualHosts."documenso.example.com" = {
    enableACME = true;
    forceSSL = true;
    locations."/".proxyPass = "http://127.0.0.1:3000";
  };
}
```

### 4. Deploy

```bash
nixos-rebuild switch
```

### 5. Verify

```bash
# Check service status
systemctl status documenso

# Check logs
journalctl -u documenso -f

# Test health endpoint
curl http://localhost:3000/api/health

# Test certificate status
curl http://localhost:3000/api/certificate-status
```

## Configuration Options

### Database

```nix
services.documenso.database = {
  host = "postgres.internal";      # PostgreSQL host
  port = 5432;                     # PostgreSQL port (default: 5432)
  name = "documenso";              # Database name (default: "documenso")
  user = "documenso";              # Database user (default: "documenso")
  passwordFile = "/run/secrets/db-password";  # REQUIRED: Password file
};
```

### SMTP

```nix
services.documenso.smtp = {
  host = "localhost";              # SMTP host
  port = 25;                       # SMTP port (default: 25)
  fromName = "Documenso";          # Sender name
  fromAddress = "noreply@example.com";  # REQUIRED: Sender email

  # Optional: SMTP authentication
  username = "smtp-user";
  passwordFile = "/run/secrets/smtp-password";

  # Optional: TLS
  secure = true;
  unsafeIgnoreTls = false;
};
```

### Storage

#### S3 (Recommended)

```nix
services.documenso.storage = {
  type = "s3";
  bucket = "documenso-documents";
  endpoint = "s3.eu-west-1.amazonaws.com";  # AWS endpoint
  region = "eu-west-1";
  credentialsFile = "/run/secrets/s3-credentials";
  forcePathStyle = false;  # Set true for MinIO
};
```

**S3 credentials file format:**
```bash
AWS_ACCESS_KEY_ID=AKIAIOSFODNN7EXAMPLE
AWS_SECRET_ACCESS_KEY=wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY
```

#### Database Storage

```nix
services.documenso.storage.type = "database";
# PDFs stored in PostgreSQL (not recommended for production)
```

### Background Jobs

#### BullMQ (Recommended - supports scheduled reminders)

```nix
services.documenso.jobs = {
  provider = "bullmq";
  redis = {
    host = "127.0.0.1";  # Local Redis (auto-enabled)
    port = 6379;
    # Optional: passwordFile for authenticated Redis
  };
};
```

#### Local (PostgreSQL-based, no scheduled jobs)

```nix
services.documenso.jobs.provider = "local";
```

### PDF Signing Certificate

#### Auto-Generate (Testing/Development)

```nix
services.documenso.signing = {
  autoGenerate = true;
  passphraseFile = "/run/secrets/cert-passphrase";
  # Certificate generated at: /var/lib/documenso/cert.p12
};
```

#### Provide Your Own (Production)

```nix
services.documenso.signing = {
  autoGenerate = false;
  certificateFile = "/var/lib/documenso/production-cert.p12";
  passphraseFile = "/run/secrets/cert-passphrase";
};
```

**Generate production certificate:**
```bash
# Generate private key and certificate
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout private.key \
  -out certificate.crt \
  -subj "/C=NL/O=Your Organization/CN=documenso.example.com"

# Create PKCS#12 bundle
openssl pkcs12 -export \
  -out cert.p12 \
  -inkey private.key \
  -in certificate.crt \
  -passout pass:YOUR_PASSPHRASE

# Copy to server
scp cert.p12 server:/var/lib/documenso/production-cert.p12
```

### Features

```nix
services.documenso.features = {
  disableSignup = false;                    # Disable /signup page
  allowedSignupDomains = [ "example.com" ]; # Restrict signup by email domain
  disableTelemetry = true;                  # Disable anonymous telemetry
};
```

### Extra Environment Variables

```nix
services.documenso.extraEnv = {
  # OAuth providers
  NEXT_PRIVATE_GOOGLE_CLIENT_ID = "...";
  NEXT_PRIVATE_GOOGLE_CLIENT_SECRET = "...";

  # Any other Documenso environment variable
};
```

## Architecture

```
┌─────────────────────────────────────────────────────┐
│                                                     │
│   Nginx/Traefik (SSL)                              │
│         │                                           │
│         ▼                                           │
│   Documenso (Node.js)                              │
│   Port 3000                                         │
│         │                                           │
│    ┌────┴─────┬──────────┬──────────┐             │
│    ▼          ▼          ▼          ▼              │
│  PostgreSQL  Redis    S3 Storage  SMTP             │
│  (external) (local)   (external)  (Postfix)        │
│                                                     │
└─────────────────────────────────────────────────────┘
```

## Maintenance

### Viewing Logs

```bash
# Follow logs
journalctl -u documenso -f

# Last 100 lines
journalctl -u documenso -n 100

# Logs since last boot
journalctl -u documenso -b
```

### Restarting Service

```bash
systemctl restart documenso
```

### Upgrading

Documenso automatically runs database migrations on startup.

```bash
# Update nixpkgs (gets new Documenso version)
# Rebuild system
nixos-rebuild switch

# Service restarts automatically
# Migrations run automatically
```

**IMPORTANT:** Always backup your PostgreSQL database before upgrading:

```bash
pg_dump -h postgres.internal -U documenso documenso > backup.sql
```

### Rollback

If upgrade fails:

```bash
# Restore database
psql -h postgres.internal -U documenso documenso < backup.sql

# Rollback NixOS
nixos-rebuild switch --rollback
```

## Troubleshooting

### Service Won't Start

```bash
# Check service status
systemctl status documenso

# Check environment file generation
systemctl status documenso-env

# View full logs
journalctl -u documenso -xe
```

### Database Connection Errors

```bash
# Test database connectivity
psql -h postgres.internal -U documenso -d documenso

# Check database password file
cat /run/agenix/documenso-db-password

# Verify environment variables
systemctl show documenso | grep NEXT_PRIVATE_DATABASE_URL
```

### Redis Connection Errors

```bash
# Check Redis status
systemctl status redis-documenso

# Test Redis connectivity
redis-cli -p 6379 ping
```

### Certificate Errors

```bash
# Check certificate status endpoint
curl http://localhost:3000/api/certificate-status

# Verify certificate file exists
ls -la /var/lib/documenso/cert.p12

# Check certificate file permissions
stat /var/lib/documenso/cert.p12
# Should be: 0400, owner: documenso
```

### S3 Upload Errors

```bash
# Verify S3 credentials are loaded
systemctl cat documenso | grep AWS_ACCESS_KEY_ID

# Test S3 access manually
aws s3 ls s3://your-bucket --profile your-profile
```

## Security Recommendations

1. **Use agenix or sops-nix** for secret management
2. **Enable HTTPS** on reverse proxy (Let's Encrypt)
3. **Restrict signup domains** in production
4. **Use proper SSL certificate** for PDF signing (not self-signed)
5. **Regular database backups**
6. **Monitor logs** for suspicious activity
7. **Keep nixpkgs updated** for security patches

## Performance Tuning

### Redis Memory

For high-volume deployments:

```nix
services.redis.servers.documenso.maxmemory = "1gb";
```

### PostgreSQL Connection Pool

Use external connection pooler (PgBouncer) for better scalability:

```nix
services.documenso.database = {
  host = "pgbouncer.internal";  # Point to PgBouncer
  port = 6432;
};
```

## MinIO S3 Storage Example

For self-hosted S3-compatible storage:

```nix
services.documenso.storage = {
  type = "s3";
  bucket = "documenso";
  endpoint = "minio.internal:9000";
  region = "us-east-1";  # MinIO default
  forcePathStyle = true;  # Required for MinIO
  credentialsFile = config.age.secrets.minio-credentials.path;
};
```

## Contributing

This module follows NixOS module conventions. See `nixos-module.nix` for implementation.

To update the Documenso package version, submit a PR to nixpkgs updating `pkgs/by-name/do/documenso/package.nix`.

## License

AGPL-3.0 (same as Documenso)

## Support

- Documenso documentation: https://docs.documenso.com
- NixOS manual: https://nixos.org/manual/nixos/stable/
- Issues: https://github.com/documenso/documenso/issues
