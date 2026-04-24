# Documenso

Open-source document signing platform (DocuSign alternative).

## Features

- **Pure NixOS** - Uses `pkgs.documenso`, no Docker
- **PostgreSQL** - External database with automatic Prisma migrations
- **BullMQ/Redis** - Scheduled reminders and background jobs
- **S3 storage** - S3-compatible object storage for PDFs
- **SMTP** - Email notifications via SMTP relay
- **PDF signing** - Auto-generate or provide X.509 certificates
- **Security** - Agenix secrets, systemd hardening

## Documentation

For complete deployment instructions, advanced configuration, and detailed troubleshooting, see the **[Administration Guide](documenso-admin.md)**.

## Quick Start

**1. Generate Secrets**
```bash
openssl rand -hex 32 > nextauth-secret.txt
openssl rand -hex 32 > encryption-key.txt
openssl rand -hex 32 > encryption-secondary-key.txt
openssl rand -base64 24 > cert-passphrase.txt
openssl rand -base64 32 > db-password.txt

# S3 credentials
cat > s3-creds.txt <<EOF
AWS_ACCESS_KEY_ID=AKIAXX
AWS_SECRET_ACCESS_KEY=secretXX
EOF

# Encrypt with agenix
for f in *.txt; do agenix -e secrets/${f%.txt}.age < $f; done
shred -u *.txt
```

**2. Configure**
```nix
{
  age.secrets = {
    documenso-db-password.file = ./secrets/db-password.age;
    documenso-nextauth.file = ./secrets/nextauth-secret.age;
    documenso-encryption-key.file = ./secrets/encryption-key.age;
    documenso-encryption-secondary-key.file = ./secrets/encryption-secondary-key.age;
    documenso-cert-passphrase.file = ./secrets/cert-passphrase.age;
    documenso-s3.file = ./secrets/s3-creds.age;
  };

  services.documenso = {
    enable = true;
    publicUrl = "https://docs.example.com";

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
      bucket = "documenso-docs";
      region = "eu-west-1";
      credentialsFile = config.age.secrets.documenso-s3.path;
    };

    jobs.provider = "bullmq";  # or "local" (no scheduled jobs)

    secrets = {
      nextAuthSecretFile = config.age.secrets.documenso-nextauth.path;
      encryptionKeyFile = config.age.secrets.documenso-encryption-key.path;
      encryptionSecondaryKeyFile = config.age.secrets.documenso-encryption-secondary-key.path;
    };

    signing = {
      autoGenerate = true;  # or provide certificateFile
      passphraseFile = config.age.secrets.documenso-cert-passphrase.path;
    };
  };

  services.nginx.virtualHosts."docs.example.com" = {
    enableACME = true;
    forceSSL = true;
    locations."/".proxyPass = "http://127.0.0.1:3000";
  };
}
```

## Configuration Options

### Database
```nix
database = {
  host = "postgres.internal";
  port = 5432;  # default
  name = "documenso";  # default
  user = "documenso";  # default
  passwordFile = "/run/secrets/db-password";  # REQUIRED
};
```

### SMTP
```nix
smtp = {
  host = "localhost";
  port = 25;  # or 587 (STARTTLS), 465 (TLS)
  fromAddress = "noreply@example.com";  # REQUIRED
  fromName = "Documenso";

  # Method 1: Separate credentials
  username = "smtp-user";
  passwordFile = "/run/secrets/smtp-password";

  # Method 2: Combined credentials file
  # credentialsFile = config.age.secrets.smtp-creds.path;
  # Format: SMTP_USERNAME=user\nSMTP_PASSWORD=pass

  secure = false;  # false=STARTTLS(587), true=TLS(465)
};
```

**AWS SES**: Use SES SMTP credentials (not IAM keys), port 587 with `secure = false`.

### Storage

**S3** (recommended):
```nix
storage = {
  type = "s3";
  bucket = "documenso-docs";
  endpoint = "s3.eu-west-1.amazonaws.com";
  region = "eu-west-1";
  credentialsFile = "/run/secrets/s3-creds";
  forcePathStyle = false;  # true for MinIO
};
```

Credentials format: `AWS_ACCESS_KEY_ID=XX\nAWS_SECRET_ACCESS_KEY=YY`

**Database** (not recommended for production):
```nix
storage.type = "database";  # PDFs in PostgreSQL
```

### Background Jobs

**BullMQ** (recommended - supports scheduled reminders):
```nix
jobs = {
  provider = "bullmq";
  redis = {
    host = "127.0.0.1";  # auto-enabled
    port = 6379;
    # passwordFile = "/run/secrets/redis-password";  # optional
  };
};
```

**Local** (PostgreSQL-based, no scheduled jobs):
```nix
jobs.provider = "local";
```

### PDF Signing Certificate

**Auto-generate** (testing/development):
```nix
signing = {
  autoGenerate = true;
  passphraseFile = "/run/secrets/cert-passphrase";
  # Generated at: /var/lib/documenso/cert.p12
};
```

**Production certificate**:
```bash
# Create production cert
openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
  -keyout key.key -out cert.crt \
  -subj "/C=NL/O=Company/CN=docs.example.com"

openssl pkcs12 -export -out cert.p12 \
  -inkey key.key -in cert.crt \
  -passout pass:PASSPHRASE

# Deploy
scp cert.p12 server:/var/lib/documenso/production-cert.p12
```

```nix
signing = {
  autoGenerate = false;
  certificateFile = "/var/lib/documenso/production-cert.p12";
  passphraseFile = "/run/secrets/cert-passphrase";
};
```

### Features
```nix
features = {
  disableSignup = false;  # Disable /signup page
  allowedSignupDomains = [ "company.com" ];  # Restrict by email domain
  disableTelemetry = true;  # Disable anonymous telemetry
};
```

### Extra Environment
```nix
extraEnv = {
  NEXT_PRIVATE_GOOGLE_CLIENT_ID = "...";
  NEXT_PRIVATE_GOOGLE_CLIENT_SECRET = "...";
  # Any other Documenso environment variable
};
```

## Maintenance

```bash
# View logs
journalctl -u documenso -f

# Restart
systemctl restart documenso

# Upgrade (automatic migrations)
nixos-rebuild switch

# Backup database first!
pg_dump -h postgres.internal -U documenso documenso > backup.sql

# Rollback if needed
psql -h postgres.internal -U documenso < backup.sql
nixos-rebuild switch --rollback
```

## Troubleshooting

**Service won't start**
```bash
systemctl status documenso documenso-env
journalctl -u documenso -xe
```

**Database errors**
```bash
# Test connection
psql -h postgres.internal -U documenso -d documenso

# Check password
cat /run/agenix/documenso-db-password

# Verify env
systemctl show documenso | grep DATABASE_URL
```

**Redis errors**
```bash
systemctl status redis-documenso
redis-cli -p 6379 ping
```

**Certificate errors**
```bash
curl http://localhost:3000/api/certificate-status
ls -la /var/lib/documenso/cert.p12  # Should be 0400, owner: documenso
```

**Playwright browser errors** (document completion fails):

`Executable doesn't exist at .../chromium_headless_shell-1169/chrome-linux/headless_shell`

This means the Playwright browser version compatibility symlink failed. Check:
```bash
# Verify symlink exists
ls -la /var/lib/documenso/.cache/ms-playwright/chromium_headless_shell-1169

# Check service logs for setup errors
journalctl -u documenso | grep "Playwright browser setup"

# Verify playwright-driver is available
nix-store -q --references /run/current-system | grep playwright
```

The module automatically creates a symlink from Documenso's expected version (1169) to the actual nixpkgs version. This is handled at service startup via ExecStartPre. See [issue #13](https://github.com/wearetechnative/elastinix/issues/13) for details.

**S3 endpoint errors** (`Invalid endpoint`):

Ensure endpoint includes `https://` protocol prefix:
```nix
storage.endpoint = "https://s3.eu-west-1.amazonaws.com";  # Correct
# NOT: "s3.eu-west-1.amazonaws.com"  # Missing protocol
```

**S3 CORS errors** (PDFs won't load in browser):
```json
{
  "CORSRules": [{
    "AllowedOrigins": ["https://your-domain.com"],
    "AllowedMethods": ["GET", "HEAD"],
    "AllowedHeaders": ["*"],
    "MaxAgeSeconds": 3000
  }]
}
```
Apply: `aws s3api put-bucket-cors --bucket your-bucket --cors-configuration file://cors.json`

**SMTP errors**

`535 Authentication Invalid`: Use SES SMTP credentials (not IAM keys)

`SSL wrong version`: Port/TLS mismatch - use `secure=false` for port 587, `secure=true` for port 465

**Emails not sending**:
```bash
# Check distribution method
sudo -u postgres psql -d documenso -c \
  "SELECT \"distributionMethod\" FROM \"DocumentMeta\" LIMIT 1;"
# Should be EMAIL, not NONE

# Check job processing
journalctl -u documenso | grep -i "Submitting job"
redis-cli -p 6379 keys '*'
```

## Security

1. Use agenix/sops-nix for secrets
2. Enable HTTPS on reverse proxy
3. Restrict signup domains in production
4. Use proper SSL certificate for PDF signing
5. Regular database backups
6. Monitor logs
7. Keep nixpkgs updated

## Performance

**Redis memory** (high-volume):
```nix
services.redis.servers.documenso.maxmemory = "1gb";
```

**PostgreSQL pooler** (scalability):
```nix
database = {
  host = "pgbouncer.internal";
  port = 6432;
};
```

## References

- [Documenso Docs](https://docs.documenso.com)
- [NixOS Manual](https://nixos.org/manual/nixos/stable/)
