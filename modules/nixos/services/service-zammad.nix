{ config, pkgs, tfvars, lib, ... }:
let
  cfg = config.elastinix.services.zammad;
  infra_environment = tfvars.infra_environment;
  environment_domain = tfvars.environment_domain;

  # Zammad 7.2 requires Elasticsearch >= 8.15; nixpkgs only ships 7.17. Built
  # here (no overlay), so pkgs.elasticsearch is unchanged for other modules.
  elasticsearchPackage = pkgs.callPackage ../../../pkgs/elasticsearch/package.nix { };
in
  {
  options.elastinix.services.zammad = {

    enable = lib.mkEnableOption "Zammad";

    package = lib.mkOption {
      type = lib.types.package;
      description = ''
        Zammad package to run. Defaults to the elastinix build of the upstream
        source pinned in pkgs/zammad/source.json, independent of the nixpkgs pin.
      '';
      # Built per service with callPackage (no overlay), so pkgs.zammad stays
      # untouched for other modules and the upstream module can still
      # .override { dataDir } it.
      default = pkgs.callPackage ../../../pkgs/zammad/package.nix { };
      defaultText = lib.literalExpression "pkgs.callPackage <elastinix>/pkgs/zammad/package.nix { }";
    };

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

    services.zammad = {
      package = cfg.package;
      enable = true;
      host = "0.0.0.0";
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
      package = elasticsearchPackage;
      dataDir = "/var/lib/elasticsearch";
      # The upstream module's single_node also sets
      # gateway.auto_import_dangling_indices, which Elasticsearch 8 rejects.
      single_node = false;
      # ingest-attachment is a bundled module since 8.4, so no plugins.
      # Local-only node: no xpack security (it would auto-enable TLS and
      # passwords on first start) and no machine learning.
      extraConf = ''
        discovery.type: single-node
        xpack.security.enabled: false
        xpack.ml.enabled: false
        http.max_content_length: 400mb
      '';
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
      # Same locations as the upstream module's nginx.configure vhost. Zammad
      # 7.2 takes the scheme from X-Forwarded-Proto (recommendedProxySettings)
      # and authenticates the legacy WebSocket from the session cookie.
      locations = {
        "/" = {
          proxyPass = "http://127.0.0.1:${toString config.services.zammad.port}";
          recommendedProxySettings = true;
        };
        "/cable" = {
          proxyPass = "http://127.0.0.1:${toString config.services.zammad.port}";
          proxyWebsockets = true;
          recommendedProxySettings = true;
        };
        "/ws" = {
          proxyPass = "http://127.0.0.1:${toString config.services.zammad.websocketPort}";
          proxyWebsockets = true;
          recommendedProxySettings = true;
        };
      };
    };
  };
}
