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

        ENCRYPTION_KEY MUST be a valid Fernet key:
          python3 -c 'from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())'
      '';
      example = "config.age.secrets.optscale.path";
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
