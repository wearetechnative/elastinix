{ config, lib, inputs, tfvars, ... }:
let
  environment_domain = tfvars.environment_domain;
  cfg = config.elastinix.services.optscale;
in
{
  options.elastinix.services.optscale = {
    enable = lib.mkEnableOption "the OptScale FinOps appliance (full stack on one instance)";

    subdomain = lib.mkOption {
      type = lib.types.str;
      default = "optscale";
      description = "Subdomain under tfvars.environment_domain for the OptScale UI (e.g. optscale.<domain>).";
    };

    secretsFile = lib.mkOption {
      type = lib.types.path;
      description = ''
        Path to the OptScale secrets EnvironmentFile (use agenix). It supplies every
        OptScale secret at runtime and is used both by the configurator (as root) and
        by MinIO (as its rootCredentialsFile), so it MUST be readable by both:
        declare the age secret with `owner = "root"; group = "minio"; mode = "0440";`.

        Required keys (KEY=value, one per line):
          MINIO_ROOT_USER, MINIO_ROOT_PASSWORD, MARIADB_PASSWORD, RABBIT_PASSWORD,
          CLUSTER_SECRET, ENCRYPTION_KEY, ENCRYPTION_SALT, ENCRYPTION_SALT_AUTH

        Additionally required when `smtp.enable` is set:
          SMTP_LOGIN, SMTP_PASSWORD

        SMTP_LOGIN may be empty (OptScale then authenticates with `smtp.from`), but
        the key must be present. With `smtp.enable = false` neither key is read. If
        either is missing while SMTP is enabled the configurator fails at boot naming
        it, and never writes /configured — so the appliance does not come up
        half-configured.

        ENCRYPTION_KEY MUST be a valid Fernet key:
          python3 -c 'from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())'
      '';
      example = "config.age.secrets.optscale.path";
    };

    smtp = {
      enable = lib.mkEnableOption ''
        outbound email (verification, password reset, invites, scheduled reports).

        When disabled, OptScale seeds no SMTP configuration and switches email
        verification off, so users are created already verified and no mail is
        enqueued that cannot be delivered. When enabled, verification is switched on
        and mail is sent for real — so the credentials below must actually work,
        otherwise signup mail silently fails to arrive
      '';

      server = lib.mkOption {
        type = lib.types.str;
        example = "email-smtp.eu-central-1.amazonaws.com";
        description = "SMTP relay hostname (e.g. an SES regional endpoint).";
      };

      port = lib.mkOption {
        type = lib.types.port;
        default = 587;
        description = "SMTP relay port. 587 for STARTTLS, 465 for implicit TLS.";
      };

      from = lib.mkOption {
        type = lib.types.str;
        default = "no-reply@${environment_domain}";
        defaultText = lib.literalExpression ''"no-reply@''${tfvars.environment_domain}"'';
        description = ''
          Envelope/from address. Must be an address the relay is allowed to send as
          (a verified identity, on SES). Also used as the SMTP login when SMTP_LOGIN
          is empty.
        '';
      };

      protocol = lib.mkOption {
        type = lib.types.enum [ "TLS" "SSL" ];
        default = "TLS";
        description = ''
          "TLS" means STARTTLS on a plain connection (port 587); "SSL" means implicit
          TLS (port 465). These are the only two values OptScale accepts — it rejects
          anything else at send time with only a log line, so the type rejects them
          here instead.
        '';
      };
    };
  };

  config = lib.mkIf cfg.enable {
    # Pin the substrate to OptScale's tested versions (ClickHouse 24.12 /
    # RabbitMQ 4.1.4) and permit the datastores. Scoped to this machine via
    # `enable` — an OptScale box is a dedicated appliance, so overriding
    # clickhouse/rabbitmq system-wide here is safe.
    nixpkgs.overlays = [ inputs.optscale.overlays.default ];
    nixpkgs.config.allowUnfreePredicate = pkg: lib.hasPrefix "mongodb" (lib.getName pkg);
    nixpkgs.config.allowInsecurePredicate = pkg: lib.getName pkg == "minio";

    # Bring up the whole appliance (substrate + configurator + services + ngui);
    # secrets come from the agenix-managed EnvironmentFile.
    services.optscale.enable = true;
    services.optscale.secrets.environmentFile = cfg.secretsFile;

    # The host used to build the links inside generated email. OptScale defaults it
    # to "localhost", which produces verification links nobody can act on — set it
    # to the same FQDN nginx serves the UI on.
    services.optscale.configurator.publicHost = "${cfg.subdomain}.${environment_domain}";

    # Guarded so `server` (which has no sensible default) is only demanded when SMTP
    # is actually in use; without the guard every OptScale host would have to define
    # a relay it never talks to.
    services.optscale.smtp = lib.mkIf cfg.smtp.enable {
      enable = true;
      inherit (cfg.smtp)
        server
        port
        from
        protocol
        ;
    };

    # Front the ngui UI (localhost:4000) with TLS; the backend services stay on
    # localhost (the BFF proxies them internally).
    services.nginx.virtualHosts."${cfg.subdomain}.${environment_domain}" = {
      enableACME = true;
      forceSSL = true;
      locations."/" = {
        proxyPass = "http://127.0.0.1:4000";
        proxyWebsockets = true;
      };
    };
  };
}
