# Example NixOS configuration for Documenso
#
# This example shows how to deploy Documenso with:
# - External PostgreSQL database
# - BullMQ (Redis) for background jobs
# - S3 storage for PDFs
# - agenix for secret management
# - Auto-generated self-signed certificate (for testing)

{ config, pkgs, ... }:

{
  # Module is automatically available via elastinix
  # No imports needed - use services.documenso directly

  # Secret management with agenix
  age.secrets = {
    # Database password
    documenso-db-password = {
      file = ./secrets/db-password.age;
      owner = "documenso";
      mode = "0400";
    };

    # Application secrets (generate with: openssl rand -hex 32)
    documenso-nextauth = {
      file = ./secrets/nextauth.age;
      owner = "documenso";
      mode = "0400";
    };

    documenso-encryption-key = {
      file = ./secrets/encryption-key.age;
      owner = "documenso";
      mode = "0400";
    };

    documenso-encryption-secondary-key = {
      file = ./secrets/encryption-secondary-key.age;
      owner = "documenso";
      mode = "0400";
    };

    # Certificate passphrase
    documenso-cert-passphrase = {
      file = ./secrets/cert-passphrase.age;
      owner = "documenso";
      mode = "0400";
    };

    # S3 credentials
    documenso-s3-credentials = {
      file = ./secrets/s3-credentials.age;
      owner = "documenso";
      mode = "0400";
    };
  };

  # Documenso service configuration
  services.documenso = {
    enable = true;

    # Public URL (must match your reverse proxy)
    publicUrl = "https://documenso.example.com";

    # Database configuration (external PostgreSQL)
    database = {
      host = "postgres.internal.example.com";
      port = 5432;
      name = "documenso";
      user = "documenso";
      passwordFile = config.age.secrets.documenso-db-password.path;
    };

    # SMTP configuration (local Postfix with AWS SES relay)
    smtp = {
      host = "localhost";
      port = 25;
      fromName = "Document Signing";
      fromAddress = "noreply@example.com";
      # No username/password needed for local relay
    };

    # S3 storage configuration
    storage = {
      type = "s3";
      bucket = "documenso-documents-prod";
      endpoint = "s3.eu-west-1.amazonaws.com";
      region = "eu-west-1";
      credentialsFile = config.age.secrets.documenso-s3-credentials.path;
    };

    # Background jobs with BullMQ (Redis)
    jobs = {
      provider = "bullmq";  # Enables scheduled reminders
      redis = {
        host = "127.0.0.1";
        port = 6379;
        # No password needed for local Redis
      };
    };

    # Secrets
    secrets = {
      nextAuthSecretFile = config.age.secrets.documenso-nextauth.path;
      encryptionKeyFile = config.age.secrets.documenso-encryption-key.path;
      encryptionSecondaryKeyFile = config.age.secrets.documenso-encryption-secondary-key.path;
    };

    # PDF signing certificate
    signing = {
      # Auto-generate self-signed certificate (good for testing)
      autoGenerate = true;
      passphraseFile = config.age.secrets.documenso-cert-passphrase.path;

      # For production, provide your own certificate:
      # autoGenerate = false;
      # certificateFile = "/var/lib/documenso/production-cert.p12";
    };

    # Optional features
    features = {
      disableSignup = false;
      allowedSignupDomains = [ "example.com" ];  # Only allow @example.com emails
      disableTelemetry = true;
    };
  };

  # Reverse proxy (nginx)
  services.nginx = {
    enable = true;

    virtualHosts."documenso.example.com" = {
      enableACME = true;
      forceSSL = true;

      locations."/" = {
        proxyPass = "http://127.0.0.1:3000";
        proxyWebsockets = true;
        extraConfig = ''
          proxy_set_header Host $host;
          proxy_set_header X-Real-IP $remote_addr;
          proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
          proxy_set_header X-Forwarded-Proto $scheme;
        '';
      };
    };
  };

  # Firewall
  networking.firewall.allowedTCPPorts = [ 80 443 ];

  # Backup recommendation (not automated by this module)
  # - PostgreSQL database (pg_dump)
  # - S3 bucket (handled by AWS)
  # - Certificate file: /var/lib/documenso/cert.p12
}
