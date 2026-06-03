{ config, lib, tfvars, pkgs, ... }:

let
  cfg = config.elastinix.services.atuin;
  environment_domain = tfvars.environment_domain;
in
  {

  options.elastinix.services.atuin = {
    enable = lib.mkEnableOption "Atuin shell-history sync server";

    package = lib.mkOption {
      type        = lib.types.package;
      default     = pkgs.atuin;
      defaultText = lib.literalExpression "pkgs.atuin";
      description = "The Atuin package to run as the server.";
    };

    host = lib.mkOption {
      type        = lib.types.str;
      default     = "127.0.0.1";
      description = "Address the Atuin server listens on. Defaults to loopback so only the local nginx reverse proxy can reach it.";
    };

    port = lib.mkOption {
      type        = lib.types.port;
      default     = 8888;
      description = "Port the Atuin server listens on (proxied by nginx).";
    };

    open_registration = lib.mkOption {
      type        = lib.types.bool;
      default     = false;
      description = "Allow new user registrations on the Atuin server. Disabled by default because the server is publicly exposed through nginx.";
    };

    max_history_length = lib.mkOption {
      type        = lib.types.int;
      default     = 8192;
      description = "Maximum length of each history item the Atuin server stores.";
    };

    create_postgresql_database = lib.mkOption {
      type        = lib.types.bool;
      default     = true;
      description = "Whether to create and manage a local PostgreSQL database and user (both named `atuin`) for Atuin, connected over a unix socket. Set to false to point Atuin at an external database via `environment_file`.";
    };

    environment_file = lib.mkOption {
      type        = lib.types.nullOr lib.types.path;
      default     = null;
      description = ''
        Path to an environment file - typically an agenix-decrypted secret - read by
        systemd before the service starts. Use it to provide `ATUIN_DB_URI` for an
        external database, e.g. `ATUIN_DB_URI=postgres://atuin:password@db.example.com/atuin`.
        Required when `create_postgresql_database` is false. The file is read by systemd
        as root, so the unprivileged (DynamicUser) service does not need access to it.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.create_postgresql_database || cfg.environment_file != null;
        message = "elastinix.services.atuin: set `environment_file` (providing ATUIN_DB_URI) when `create_postgresql_database` is false.";
      }
    ];

    services.atuin = {
      enable  = true;
      package = cfg.package;

      host             = cfg.host;
      port             = cfg.port;
      openRegistration = cfg.open_registration;
      maxHistoryLength = cfg.max_history_length;

      database = {
        createLocally = cfg.create_postgresql_database;
        # For the local database the module's default unix-socket URI is used. For an
        # external database set uri to null so ATUIN_DB_URI is taken from environment_file.
        uri = lib.mkIf (!cfg.create_postgresql_database) null;
      };
    };

    systemd.services.atuin.serviceConfig.EnvironmentFile =
      lib.mkIf (cfg.environment_file != null) [ cfg.environment_file ];

    services.nginx.virtualHosts."atuin.${environment_domain}" = {
      enableACME = true;
      forceSSL = true;
      locations = {
        "/" = {
          proxyPass = "http://127.0.0.1:${toString cfg.port}";
        };
      };
    };
  };
}
