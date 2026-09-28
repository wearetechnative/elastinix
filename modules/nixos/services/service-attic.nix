{ lib, config, tfvars, ... }:
let
  cfg = config.elastinix.services.attic;
  environment_domain = tfvars.environment_domain;
  infra_environment = tfvars.infra_environment;
in

  {
  options.elastinix.services.attic = {

    enable = lib.mkEnableOption "Attic cache";

    environment_file = lib.mkOption {
      type = lib.types.str;
      description = ''
        Absolute path to the environment file (typically an agenix secret) passed
        to atticd as systemd `EnvironmentFile`. It must set
        `ATTIC_SERVER_TOKEN_RS256_SECRET_BASE64` and, unless `database_url` is set,
        `ATTIC_SERVER_DATABASE_URL`.
      '';
    };

    s3_bucket = lib.mkOption {
      type = lib.types.str;
      description = ''
        S3 bucket name prefix for NAR/chunk storage; the module appends
        `-''${infra_environment}` from tfvars.
      '';
    };

    garbage_collection = {
      interval = lib.mkOption {
        type = lib.types.str;
        default = "12 hours";
        description = ''
          How often the collector runs, as a humantime expression.

          This is attic's own default, rendered explicitly so that the generated
          configuration states what the collector does. `"0"` disables the
          collector entirely, including the reaping of orphans.
        '';
      };

      default_retention_period = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = "90 days";
        example = "2 years";
        description = ''
          Retention period for caches that set none of their own, as a humantime
          expression. `null` renders `"0"`, attic's encoding for "time-based
          collection off", which leaves only the reaping of orphans.

          An object is deleted only when **both** its `created_at` and its
          `last_accessed_at` precede the cutoff, so this means old *and* unused,
          never merely old. Only downloading the NAR counts as access; fetching
          the `.narinfo` does not, so a host that already holds a path does not
          keep the cached copy alive by checking for it.

          A cache that sets its own retention through
          `attic cache configure <name> --retention-period` overrides this.
        '';
      };
    };

    database_url = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "sqlite:///var/lib/atticd/server.db?mode=rwc";
      description = ''
        Database URL rendered into the attic server configuration.

        `null` (the default) leaves `database.url` out of the generated TOML, so
        attic takes it from `ATTIC_SERVER_DATABASE_URL` in `environment_file`.
        This is the intended setup for PostgreSQL: the generated configuration
        lives in the world-readable Nix store, so a URL with a password must never
        be set here (an assertion refuses one). If the variable is missing, atticd
        fails to start rather than falling back to SQLite.

        The database holds every cache's signing keypair and the chunk index; the
        S3 bucket only holds the chunks. The database, not the bucket, therefore
        decides whether a cache survives an instance replacement. A SQLite URL
        puts it in atticd's state directory on the instance's root volume, where
        it is lost when the instance is replaced.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.database_url == null
          || (builtins.match "[^:]+://[^/@]*:[^/@]*@.*" cfg.database_url == null
            && builtins.match ".*[?&]password=.*" cfg.database_url == null);
        message = ''
          elastinix.services.attic.database_url contains a password. It would be
          written to the world-readable Nix store. Leave database_url null and set
          ATTIC_SERVER_DATABASE_URL in elastinix.services.attic.environment_file.
        '';
      }
    ];

    services.atticd = {
      enable = true;

      # Replace with absolute path to your credentials file
      environmentFile = cfg.environment_file;

      settings = {
        listen = "[::]:8080";
        api-endpoint = "https://attic.${environment_domain}/";

        # Data chunking
        #
        # Warning: If you change any of the values here, it will be
        # difficult to reuse existing chunks for newly-uploaded NARs
        # since the cutpoints will be different. As a result, the
        # deduplication ratio will suffer for a while after the change.
        chunking = {
          # The minimum NAR siz/tmp/attic.enve to trigger chunking
          #
          # If 0, chunking is disabled entirely for newly-uploaded NARs.
          # If 1, all NARs are chunked.
          nar-size-threshold = 64 * 1024; # 64 KiB

          # The preferred minimum size of a chunk, in bytes
          min-size = 16 * 1024; # 16 KiB

          # The preferred average size of a chunk, in bytes
          avg-size = 64 * 1024; # 64 KiB

          # The preferred maximum size of a chunk, in bytes
          max-size = 256 * 1024; # 256 KiB

        };
        # No url in the TOML: attic then reads ATTIC_SERVER_DATABASE_URL from the
        # environment file. mkForce discards the upstream mkDefault SQLite url.
        database =
          if cfg.database_url == null
          then lib.mkForce { }
          else { url = cfg.database_url; };

        garbage-collection = {
          interval = cfg.garbage_collection.interval;
          # Attic reads a zero period as "time-based collection disabled". The key
          # stays present either way, so the configuration always says what happens.
          default-retention-period =
            if cfg.garbage_collection.default_retention_period == null
            then "0"
            else cfg.garbage_collection.default_retention_period;
        };

        storage = {
          type = "s3";
          region = "eu-central-1";
          bucket = "${cfg.s3_bucket}-${infra_environment}";
        };

      };
    };

    services.nginx.virtualHosts."attic.${environment_domain}" = {
      enableACME = true;
      forceSSL = true;

      extraConfig = ''client_max_body_size 0;'';

      locations = {
        "/" = {
          proxyPass = "http://127.0.0.1:8080";
          proxyWebsockets = true;
        };
      };
    };
  };
}
