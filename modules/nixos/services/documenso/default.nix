{ config, lib, pkgs, inputs, ... }:

let
  cfg = config.services.documenso;

  inherit (lib)
    mkEnableOption mkOption mkIf mkMerge mkDefault
    types literalExpression optionalString optional;

  # Build-time Playwright browsers tree.
  #
  # Documenso's vendored Playwright expects a specific chromium-headless-shell
  # revision, which rarely matches the revision nixpkgs ships. Rather than
  # discovering and symlinking at boot (ExecStartPre), we build a read-only
  # store tree that mirrors pkgs.playwright-driver.browsers and exposes the
  # shipped chromium-headless-shell under the exact revision name Documenso
  # looks for. The expected revision is read from Documenso's own
  # playwright-core/browsers.json, so this self-corrects across future bumps.
  playwrightBrowsers = pkgs.runCommand "documenso-playwright-browsers"
    { nativeBuildInputs = [ pkgs.jq ]; } ''
      mkdir -p "$out"

      # Mirror every entry from the stock nixpkgs playwright browsers.
      for entry in ${pkgs.playwright-driver.browsers}/*; do
        ln -s "$entry" "$out/$(basename "$entry")"
      done

      # Revision Documenso's bundled Playwright expects.
      EXPECTED=$(jq -r \
        '.browsers[] | select(.name == "chromium-headless-shell") | .revision' \
        ${cfg.package}/node_modules/playwright-core/browsers.json)
      if [ -z "$EXPECTED" ] || [ "$EXPECTED" = "null" ]; then
        echo "ERROR: could not read chromium-headless-shell revision from Documenso's playwright-core/browsers.json" >&2
        exit 1
      fi

      # Revision actually shipped by nixpkgs playwright-driver.
      ACTUAL=$(ls -d ${pkgs.playwright-driver.browsers}/chromium_headless_shell-* 2>/dev/null | head -n1)
      if [ -z "$ACTUAL" ]; then
        echo "ERROR: no chromium_headless_shell-* found in ${pkgs.playwright-driver.browsers}" >&2
        echo "The nixpkgs playwright-driver does not provide a headless chromium; cannot build the bridge." >&2
        exit 1
      fi

      # Expose the shipped browser under the name Documenso looks for.
      ln -sfn "$ACTUAL" "$out/chromium_headless_shell-$EXPECTED"
      echo "playwright bridge: $(basename "$ACTUAL") -> chromium_headless_shell-$EXPECTED"
    '';
in
{
  options.services.documenso = {
    enable = mkEnableOption "Documenso document signing platform";

    package = mkOption {
      type = types.package;
      default = pkgs.documenso;
      defaultText = literalExpression "pkgs.documenso";
      description = ''
        Documenso package to use.
        Defaults to `pkgs.documenso`. On hosts enabling this service, that is
        overlaid to the 2.14.0 build from the `nixpkgs-unstable` input (see the
        overlay in this module), since the pinned `nixos-26.05` only carries
        1.12.x. Documenso honours the `PORT` environment variable natively, so
        no port patching is needed; the overlay only adds a symlink so the
        license cache file lands in the writable state dir instead of the store.
      '';
    };

    user = mkOption {
      type = types.str;
      default = "documenso";
      description = "User account under which Documenso runs";
    };

    group = mkOption {
      type = types.str;
      default = "documenso";
      description = "Group account under which Documenso runs";
    };

    stateDir = mkOption {
      type = types.path;
      default = "/var/lib/documenso";
      description = "State directory for Documenso";
    };

    publicUrl = mkOption {
      type = types.str;
      example = "https://documenso.example.com";
      description = "Public URL for the Documenso instance";
    };

    port = mkOption {
      type = types.port;
      default = 3000;
      description = "Port on which Documenso listens";
    };

    # Database configuration
    database = {
      host = mkOption {
        type = types.str;
        default = "localhost";
        description = "PostgreSQL database host";
      };

      port = mkOption {
        type = types.port;
        default = 5432;
        description = "PostgreSQL database port";
      };

      name = mkOption {
        type = types.str;
        default = "documenso";
        description = "PostgreSQL database name";
      };

      user = mkOption {
        type = types.str;
        default = "documenso";
        description = "PostgreSQL database user";
      };

      passwordFile = mkOption {
        type = types.path;
        description = "File containing PostgreSQL database password";
        example = "config.age.secrets.documenso-db-password.path";
      };
    };

    # SMTP configuration
    smtp = {
      host = mkOption {
        type = types.str;
        default = "localhost";
        description = "SMTP server host";
      };

      port = mkOption {
        type = types.port;
        default = 25;
        description = "SMTP server port";
      };

      fromName = mkOption {
        type = types.str;
        default = "Documenso";
        example = "Document Signing";
        description = "Sender name for emails";
      };

      fromAddress = mkOption {
        type = types.str;
        example = "noreply@example.com";
        description = "Sender email address";
      };

      username = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "SMTP username (optional for authenticated SMTP)";
      };

      passwordFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = "File containing SMTP password (optional)";
        example = "config.age.secrets.documenso-smtp-password.path";
      };

      credentialsFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = ''
          File containing SMTP credentials in KEY=value format (alternative to username+passwordFile):

          SMTP_USERNAME=your_username
          SMTP_PASSWORD=your_password

          Use either username+passwordFile OR credentialsFile, not both.
        '';
        example = "config.age.secrets.documenso-smtp-credentials.path";
      };

      secure = mkOption {
        type = types.bool;
        default = false;
        description = "Use TLS for SMTP connection";
      };

      unsafeIgnoreTls = mkOption {
        type = types.bool;
        default = false;
        description = "Disable TLS even if server supports STARTTLS (unsafe)";
      };
    };

    # Storage configuration
    storage = {
      type = mkOption {
        type = types.enum [ "database" "s3" ];
        default = "s3";
        description = ''
          Storage backend for PDF documents.
          - database: Store in PostgreSQL (simple but not scalable)
          - s3: Store in S3-compatible object storage (recommended)
        '';
      };

      bucket = mkOption {
        type = types.str;
        example = "documenso-documents";
        description = "S3 bucket name for document storage";
      };

      endpoint = mkOption {
        type = types.str;
        default = "https://s3.amazonaws.com";
        example = "https://s3.eu-west-1.amazonaws.com";
        description = "S3 endpoint URL (must include https:// protocol)";
      };

      region = mkOption {
        type = types.str;
        default = "us-east-1";
        example = "eu-west-1";
        description = "S3 region";
      };

      credentialsFile = mkOption {
        type = types.path;
        description = ''
          File containing S3 credentials in KEY=value format:

          AWS_ACCESS_KEY_ID=your_access_key
          AWS_SECRET_ACCESS_KEY=your_secret_key
        '';
        example = "config.age.secrets.documenso-s3.path";
      };

      forcePathStyle = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Force path-style URLs for S3 (domain.com/bucket/key instead of bucket.domain.com/key).
          Required for MinIO and some S3-compatible providers.
        '';
      };
    };

    # Background jobs configuration
    jobs = {
      provider = mkOption {
        type = types.enum [ "local" "bullmq" ];
        default = "bullmq";
        description = ''
          Background job provider:
          - local: PostgreSQL-based (simple, no scheduled jobs)
          - bullmq: Redis-based (supports scheduled reminders)
        '';
      };

      redis = {
        host = mkOption {
          type = types.str;
          default = "127.0.0.1";
          description = "Redis host (when using BullMQ)";
        };

        port = mkOption {
          type = types.port;
          default = 6379;
          description = "Redis port (when using BullMQ)";
        };

        passwordFile = mkOption {
          type = types.nullOr types.path;
          default = null;
          description = "File containing Redis password (optional)";
        };

        prefix = mkOption {
          type = types.str;
          default = "documenso";
          description = "Redis key prefix for job queue";
        };
      };
    };

    # Secrets configuration
    secrets = {
      nextAuthSecretFile = mkOption {
        type = types.path;
        description = ''
          File containing NextAuth secret (minimum 32 characters).
          Generate with: openssl rand -hex 32
        '';
        example = "config.age.secrets.documenso-nextauth.path";
      };

      encryptionKeyFile = mkOption {
        type = types.path;
        description = ''
          File containing encryption key (minimum 32 characters).
          Generate with: openssl rand -hex 32
        '';
        example = "config.age.secrets.documenso-encryption-key.path";
      };

      encryptionSecondaryKeyFile = mkOption {
        type = types.path;
        description = ''
          File containing secondary encryption key (minimum 32 characters).
          Generate with: openssl rand -hex 32
        '';
        example = "config.age.secrets.documenso-encryption-secondary-key.path";
      };
    };

    # PDF signing certificate
    signing = {
      certificateFile = mkOption {
        type = types.path;
        default = "${cfg.stateDir}/cert.p12";
        description = "Path to PKCS#12 (.p12) certificate for PDF signing";
      };

      passphraseFile = mkOption {
        type = types.path;
        description = "File containing certificate passphrase";
        example = "config.age.secrets.documenso-cert-passphrase.path";
      };

      autoGenerate = mkOption {
        type = types.bool;
        default = false;
        description = ''
          Automatically generate a self-signed certificate if certificateFile doesn't exist.
          Useful for testing/development. For production, provide a proper certificate.
        '';
      };
    };

    # Optional features
    features = {
      disableSignup = mkOption {
        type = types.bool;
        default = false;
        description = "Disable user registration via /signup page";
      };

      allowedSignupDomains = mkOption {
        type = types.listOf types.str;
        default = [];
        example = [ "example.com" "acme.org" ];
        description = "Email domains allowed to sign up (empty = all domains allowed)";
      };

      disableTelemetry = mkOption {
        type = types.bool;
        default = true;
        description = "Disable anonymous telemetry";
      };
    };

    # Extra environment variables
    extraEnv = mkOption {
      type = types.attrsOf types.str;
      default = {};
      example = {
        NEXT_PRIVATE_GOOGLE_CLIENT_ID = "...";
        NEXT_PRIVATE_GOOGLE_CLIENT_SECRET = "...";
      };
      description = "Additional environment variables to set";
    };

    environmentFiles = mkOption {
      type = types.listOf types.path;
      default = [];
      description = "Additional environment files to load";
    };
  };

  config = mkIf cfg.enable (mkMerge [
    # Common configuration
    {
      # Documenso 2.14.0 lives only in nixpkgs-unstable; the pinned nixos-26.05
      # carries 1.12.x and will not backport a major version. Pull ONLY documenso
      # and the playwright-driver the browser bridge consumes from the scoped
      # `nixpkgs-unstable` input. Scoped to this host via `enable` (a Documenso
      # box is a dedicated appliance), so the rest of the platform stays on 26.05.
      nixpkgs.overlays = [
        (final: prev:
          let unstable = inputs.nixpkgs-unstable.legacyPackages.${prev.stdenv.hostPlatform.system};
          in {
            # Documenso caches its license lookup to `.documenso-license.json`
            # at `path.join(process.cwd(), LICENSE_FILE_NAME)`. The bin/documenso
            # wrapper cd's into `$out/apps/remix` (a read-only Nix store path),
            # so the write fails with `EROFS: read-only file system`. Redirect
            # that file to the writable state dir via a store symlink; the target
            # lives under `stateDir`, which is already in ReadWritePaths.
            documenso = unstable.documenso.overrideAttrs (old: {
              postFixup = (old.postFixup or "") + ''
                ln -sfn ${cfg.stateDir}/.documenso-license.json \
                  $out/apps/remix/.documenso-license.json
              '';
            });
            playwright-driver = unstable.playwright-driver;
          })
      ];

      # Assertions
      assertions = [
        {
          assertion = cfg.storage.type == "database" || cfg.storage.bucket != "";
          message = "services.documenso.storage.bucket must be set when using S3 storage";
        }
        {
          assertion = cfg.smtp.fromAddress != "";
          message = "services.documenso.smtp.fromAddress must be set";
        }
        {
          assertion =
            (cfg.smtp.username != null && cfg.smtp.passwordFile != null && cfg.smtp.credentialsFile == null) ||
            (cfg.smtp.username == null && cfg.smtp.passwordFile == null && cfg.smtp.credentialsFile != null) ||
            (cfg.smtp.username == null && cfg.smtp.passwordFile == null && cfg.smtp.credentialsFile == null);
          message = "services.documenso.smtp: Use either username+passwordFile OR credentialsFile, not both";
        }
      ];

      # User and group
      users.users.${cfg.user} = {
        isSystemUser = true;
        group = cfg.group;
        home = cfg.stateDir;
        createHome = true;
      };

      users.groups.${cfg.group} = {};

      # State directory
      systemd.tmpfiles.rules = [
        "d '${cfg.stateDir}' 0750 ${cfg.user} ${cfg.group} - -"
      ];

      # Environment file generator
      systemd.services.documenso-env = {
        description = "Documenso Environment File Generator";
        wantedBy = [ "documenso.service" ];
        before = [ "documenso.service" ];

        serviceConfig = {
          Type = "oneshot";
          User = cfg.user;
          Group = cfg.group;
          RemainAfterExit = true;
        };

        script = ''
          # Read secrets (strip trailing newlines)
          DB_PASS=$(cat ${cfg.database.passwordFile} | tr -d '\n')
          NEXTAUTH_SECRET=$(cat ${cfg.secrets.nextAuthSecretFile} | tr -d '\n')
          ENCRYPTION_KEY=$(cat ${cfg.secrets.encryptionKeyFile} | tr -d '\n')
          ENCRYPTION_SECONDARY_KEY=$(cat ${cfg.secrets.encryptionSecondaryKeyFile} | tr -d '\n')
          SIGNING_PASSPHRASE=$(cat ${cfg.signing.passphraseFile} | tr -d '\n')

          ${optionalString (cfg.smtp.passwordFile != null) ''
            SMTP_PASSWORD=$(cat ${cfg.smtp.passwordFile} | tr -d '\n')
          ''}

          ${optionalString (cfg.smtp.credentialsFile != null) ''
            # Source SMTP credentials
            source ${cfg.smtp.credentialsFile}
          ''}

          ${optionalString (cfg.storage.type == "s3") ''
            # Source S3 credentials
            source ${cfg.storage.credentialsFile}
          ''}

          ${optionalString (cfg.jobs.provider == "bullmq" && cfg.jobs.redis.passwordFile != null) ''
            REDIS_PASSWORD=$(cat ${cfg.jobs.redis.passwordFile} | tr -d '\n')
          ''}

          # Generate .env file
          cat > ${cfg.stateDir}/.env <<EOF
          # URLs
          NEXT_PUBLIC_WEBAPP_URL=${cfg.publicUrl}
          NEXT_PRIVATE_INTERNAL_WEBAPP_URL=http://127.0.0.1:${toString cfg.port}
          PORT=${toString cfg.port}

          # Auth & Crypto
          NEXTAUTH_SECRET=$NEXTAUTH_SECRET
          NEXT_PRIVATE_ENCRYPTION_KEY=$ENCRYPTION_KEY
          NEXT_PRIVATE_ENCRYPTION_SECONDARY_KEY=$ENCRYPTION_SECONDARY_KEY

          # Database
          NEXT_PRIVATE_DATABASE_URL=postgresql://${cfg.database.user}:$DB_PASS@${cfg.database.host}:${toString cfg.database.port}/${cfg.database.name}
          NEXT_PRIVATE_DIRECT_DATABASE_URL=postgresql://${cfg.database.user}:$DB_PASS@${cfg.database.host}:${toString cfg.database.port}/${cfg.database.name}

          # SMTP
          NEXT_PRIVATE_SMTP_TRANSPORT=smtp-auth
          NEXT_PRIVATE_SMTP_HOST=${cfg.smtp.host}
          NEXT_PRIVATE_SMTP_PORT=${toString cfg.smtp.port}
          NEXT_PRIVATE_SMTP_FROM_NAME=${cfg.smtp.fromName}
          NEXT_PRIVATE_SMTP_FROM_ADDRESS=${cfg.smtp.fromAddress}
          ${optionalString (cfg.smtp.username != null) ''
            NEXT_PRIVATE_SMTP_USERNAME=${cfg.smtp.username}
          ''}
          ${optionalString (cfg.smtp.passwordFile != null) ''
            NEXT_PRIVATE_SMTP_PASSWORD=$SMTP_PASSWORD
          ''}
          ${optionalString (cfg.smtp.credentialsFile != null) ''
            NEXT_PRIVATE_SMTP_USERNAME=$SMTP_USERNAME
            NEXT_PRIVATE_SMTP_PASSWORD=$SMTP_PASSWORD
          ''}
          ${optionalString cfg.smtp.secure ''
            NEXT_PRIVATE_SMTP_SECURE=true
          ''}
          ${optionalString cfg.smtp.unsafeIgnoreTls ''
            NEXT_PRIVATE_SMTP_UNSAFE_IGNORE_TLS=true
          ''}

          # Storage
          NEXT_PUBLIC_UPLOAD_TRANSPORT=${cfg.storage.type}
          ${optionalString (cfg.storage.type == "s3") ''
            NEXT_PRIVATE_UPLOAD_ENDPOINT=${cfg.storage.endpoint}
            NEXT_PRIVATE_UPLOAD_REGION=${cfg.storage.region}
            NEXT_PRIVATE_UPLOAD_BUCKET=${cfg.storage.bucket}
            NEXT_PRIVATE_UPLOAD_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID
            NEXT_PRIVATE_UPLOAD_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY
            NEXT_PRIVATE_UPLOAD_FORCE_PATH_STYLE=${if cfg.storage.forcePathStyle then "true" else "false"}
          ''}

          # Background Jobs
          NEXT_PRIVATE_JOBS_PROVIDER=${cfg.jobs.provider}
          ${optionalString (cfg.jobs.provider == "bullmq") ''
            NEXT_PRIVATE_REDIS_URL=redis://${optionalString (cfg.jobs.redis.passwordFile != null) ":$REDIS_PASSWORD@"}${cfg.jobs.redis.host}:${toString cfg.jobs.redis.port}
            NEXT_PRIVATE_REDIS_PREFIX=${cfg.jobs.redis.prefix}
          ''}

          # PDF Signing
          NEXT_PRIVATE_SIGNING_PASSPHRASE=$SIGNING_PASSPHRASE
          NEXT_PRIVATE_SIGNING_LOCAL_FILE_PATH=${cfg.signing.certificateFile}

          # Features
          ${optionalString cfg.features.disableSignup ''
            NEXT_PUBLIC_DISABLE_SIGNUP=true
          ''}
          ${optionalString (cfg.features.allowedSignupDomains != []) ''
            NEXT_PRIVATE_ALLOWED_SIGNUP_DOMAINS=${lib.concatStringsSep "," cfg.features.allowedSignupDomains}
          ''}
          ${optionalString cfg.features.disableTelemetry ''
            DOCUMENSO_DISABLE_TELEMETRY=true
          ''}

          # Extra environment variables
          ${lib.concatStringsSep "\n" (lib.mapAttrsToList (name: value: "${name}=${value}") cfg.extraEnv)}
          EOF

          chmod 600 ${cfg.stateDir}/.env
        '';
      };

      # Main Documenso service
      systemd.services.documenso = {
        description = "Documenso Document Signing Service";
        wantedBy = [ "multi-user.target" ];
        after = [ "network.target" "documenso-env.service" ]
          ++ optional (cfg.jobs.provider == "bullmq") "redis-documenso.service";
        requires = [ "documenso-env.service" ]
          ++ optional (cfg.jobs.provider == "bullmq") "redis-documenso.service";

        environment = {
          NODE_ENV = "production";
          # Read-only, build-time browsers tree (see `playwrightBrowsers` above):
          # the chromium-headless-shell is exposed under the exact revision name
          # Documenso expects. No runtime symlinking or state-directory cache.
          PLAYWRIGHT_BROWSERS_PATH = playwrightBrowsers;
          PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD = "1";
          PLAYWRIGHT_SKIP_VALIDATE_HOST_REQUIREMENTS = "1";
        };

        serviceConfig = {
          Type = "simple";
          User = cfg.user;
          Group = cfg.group;
          WorkingDirectory = cfg.stateDir;
          EnvironmentFile = [ "${cfg.stateDir}/.env" ] ++ cfg.environmentFiles;

          # Pre-start script: certificate generation only.
          # Playwright browsers are provided as a build-time store path via
          # PLAYWRIGHT_BROWSERS_PATH (see `playwrightBrowsers`), so no runtime
          # browser setup step is needed.
          ExecStartPre =
            # Certificate auto-generation (conditional on cfg.signing.autoGenerate)
            optional cfg.signing.autoGenerate (pkgs.writeShellScript "documenso-gen-cert" ''
              set -euo pipefail

              if [ ! -f "${cfg.signing.certificateFile}" ]; then
                echo "Generating self-signed PDF signing certificate..."

                PASSPHRASE=$(cat ${cfg.signing.passphraseFile})

                # Extract hostname from publicUrl (strip protocol and port)
                HOSTNAME=$(echo "${cfg.publicUrl}" | sed -e 's|^[^/]*//||' -e 's|:.*||')

                # Generate RSA private key + certificate
                ${pkgs.openssl}/bin/openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
                  -keyout /tmp/documenso-key.pem \
                  -out /tmp/documenso-cert.pem \
                  -subj "/C=NL/O=Documenso/CN=$HOSTNAME"

                # Create PKCS#12 bundle with legacy RC2-40-CBC encryption
                # The Rust signing library (@documenso/pdf-sign) only supports legacy PKCS#12 format
                ${pkgs.openssl}/bin/openssl pkcs12 -export -legacy \
                  -out "${cfg.signing.certificateFile}" \
                  -inkey /tmp/documenso-key.pem \
                  -in /tmp/documenso-cert.pem \
                  -passout pass:$PASSPHRASE

                # Cleanup temp files
                rm /tmp/documenso-key.pem /tmp/documenso-cert.pem

                # Set permissions
                chmod 400 "${cfg.signing.certificateFile}"

                echo "Certificate generated at ${cfg.signing.certificateFile}"
              fi
            '');

          # Start Documenso (wrapper handles migrations automatically)
          ExecStart = "${cfg.package}/bin/documenso";

          # Restart policy
          Restart = "always";
          RestartSec = "10s";

          # Security hardening
          NoNewPrivileges = true;
          PrivateTmp = true;
          ProtectSystem = "strict";
          ProtectHome = true;
          ReadWritePaths = [ cfg.stateDir ];
          PrivateDevices = true;
          ProtectKernelTunables = true;
          ProtectKernelModules = true;
          ProtectControlGroups = true;
        };
      };
    }

    # Redis configuration (when using BullMQ)
    (mkIf (cfg.jobs.provider == "bullmq") {
      services.redis.servers.documenso = {
        enable = true;
        port = cfg.jobs.redis.port;
        bind = "127.0.0.1";

        # Persistence for job queue durability
        save = [
          [ 900 1 ]     # Save after 15 minutes if at least 1 key changed
          [ 300 10 ]    # Save after 5 minutes if at least 10 keys changed
          [ 60 10000 ]  # Save after 1 minute if at least 10000 keys changed
        ];

        # Append-only file for better durability
        appendOnly = true;
        appendFsync = "everysec";

        settings = {
          # Memory management
          maxmemory = "256mb";
          maxmemory-policy = "noeviction";  # Never evict keys (critical for jobs)

          # Additional Redis settings
          stop-writes-on-bgsave-error = "yes";
          rdbcompression = "yes";
          rdbchecksum = "yes";
        };
      };
    })
  ]);
}
