{ config, pkgs, tfvars, pkgs-zammad, lib, ... }:
let
  cfg = config.elastinix.services.zammad;
  infra_environment = tfvars.infra_environment;
  environment_domain = tfvars.environment_domain;
in
  {
  options.elastinix.services.zammad = {

    enable = lib.mkEnableOption "Zammad";

    database_username = lib.mkOption {
      type = lib.types.str;
      description = "";
    };

    database_host = lib.mkOption {
      type = lib.types.str;
      description = "";
    };

    database_port = lib.mkOption {
      type = lib.types.int;
      description = "";
    };

    database_name = lib.mkOption {
      type = lib.types.str;
      description = "";
    };

    secret_key_base_file = lib.mkOption {
      type = lib.types.str;
      description = "";
    };

    password_file = lib.mkOption {
      type = lib.types.str;
      description = "";
    };
  };

  # Only enable Zammad when in production environment
  config = lib.mkIf cfg.enable {
    config = lib.mkIf (infra_environment == "prod") {
      nixpkgs.config.allowUnfree = true;

      services.zammad = {
        package = pkgs-zammad.zammad;
        enable = true;
        host = "0.0.0.0";
        openPorts = true;
        secretKeyBaseFile = "${cfg.secret_key_base_file}";

        redis.createLocally = true;

        database.createLocally = false;
        database.host = "${cfg.database_host}";
        database.user = "${cfg.database_username}";
        database.name = "${cfg.database_name}";
        database.port = cfg.database_port;
        database.passwordFile = "${cfg.password_file}";

      };

      services.elasticsearch = {
        enable = true;
        dataDir = "/var/lib/elasticsearch";
        plugins = [ pkgs.elasticsearchPlugins.ingest-attachment ];
        extraConf = "http.max_content_length: 400mb";
        logging = ''
            logger.action.name = org.elasticsearch.action
            logger.action.level = info

            appender.console.type = Console
            appender.console.name = console
            appender.console.layout.type = PatternLayout
            appender.console.layout.pattern = [%d{ISO8601}][%-5p][%-25c{1.}] %marker%m%n
            rootLogger.level = info
            rootLogger.appenderRef.console.ref = console
        '';
      };

      services.nginx.virtualHosts."zammad.${environment_domain}" = {
        enableACME = true;
        forceSSL = true;
        locations = {
          "/" = {
            proxyPass = "http://127.0.0.1:3000";
          };
        };
      };
    };
  };
}
