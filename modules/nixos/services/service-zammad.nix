{ config, pkgs, inputs, tfvars, lib, ... }:
let
  cfg = config.elastinix.services.zammad;
  infra_environment = tfvars.infra_environment;
  environment_domain = tfvars.environment_domain;

  # Oldest release allowed against the production database (migrations are
  # forward-only). Raise this after every production upgrade.
  minimumVersion = "7.2.2";

  # Packages per `source`; attrsets are lazy, so only the selected one is built.
  # Built per service (no overlay), so pkgs.zammad stays untouched for other
  # modules and the upstream module can still .override { dataDir } it.
  unstable = inputs.nixpkgs-unstable.legacyPackages.${pkgs.stdenv.hostPlatform.system};
  packages = {
    pinned = pkgs.callPackage ../../../pkgs/zammad/package.nix { };
    nixpkgs = pkgs.zammad;
    unstable = unstable.zammad;
  };

  # Zammad 7.2 requires Elasticsearch >= 8.15; nixpkgs only ships 7.17. Built
  # here (no overlay), so pkgs.elasticsearch is unchanged for other modules.
  elasticsearchPackage = pkgs.callPackage ../../../pkgs/elasticsearch/package.nix { };
in
  {
  options.elastinix.services.zammad = {

    enable = lib.mkEnableOption "Zammad";

    source = lib.mkOption {
      type = lib.types.enum [ "pinned" "nixpkgs" "unstable" ];
      default = "pinned";
      description = ''
        Where the default `package` comes from: "pinned" builds the upstream
        source pinned in pkgs/zammad/source.json, "nixpkgs" uses pkgs.zammad,
        "unstable" uses the nixpkgs-unstable input.
      '';
    };

    package = lib.mkOption {
      type = lib.types.package;
      description = "Zammad package to run. Defaults to the package selected by `source`.";
      default = packages.${cfg.source};
      defaultText = lib.literalExpression ''
        {
          pinned = pkgs.callPackage <elastinix>/pkgs/zammad/package.nix { };
          nixpkgs = pkgs.zammad;
          unstable = inputs.nixpkgs-unstable.legacyPackages.''${system}.zammad;
        }.''${config.elastinix.services.zammad.source}
      '';
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
    warnings = lib.optional (lib.versionOlder cfg.package.version minimumVersion) ''
      elastinix.services.zammad: package version ${cfg.package.version} is older than
      the minimum version ${minimumVersion}. Zammad database migrations are
      forward-only; take a backup of the database before downgrading.
    '';

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
