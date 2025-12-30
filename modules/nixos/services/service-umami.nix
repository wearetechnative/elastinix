{lib, tfvars, config, pkgs, ...}:
let
  cfg = config.elastinix.services.umami;
  environment_domain = tfvars.environment_domain;
in
  {
  options.elastinix.services.umami = {
    enable = lib.mkEnableOption "umami server";

    create_postgresql_database = lib.mkOption {
      type        = lib.types.str;
      description = "Whether to automatically create the database for Umami using PostgreSQL. Both the database name and username will be umami, and the connection is made through unix sockets using peer authentication.";
    };

    port = lib.mkOption {
      type        = lib.types.str;
      description = "The port to listen on.";
      default     = "3000";
    };

    hostname = lib.mkOption {
      type        = lib.types.str;
      description = "The address to listen on.";
      default     = "127.0.0.1";
    };

    base_path = lib.mkOption {
      type        = lib.types.str;
      description = "Allows you to host Umami under a subdirectory. You may need to update your reverse proxy settings to correctly handle the BASE_PATH prefix.";
      default     = "";
    };

    database_url_file = lib.mkOption {
      type        = lib.types.str;
      description = "A file containing a connection string for the database. The connection string must start with postgresql:// or postgres://. The contents of the file are read through systemd credentials, therefore the user running umami does not need permissions to read the file.";
      default     = null;
    };

    app_secret_file = lib.mkOption {
      type        = lib.types.str;
      description = "A file containing a secure random string. This is used for signing user sessions. The contents of the file are read through systemd credentials, therefore the user running umami does not need permissions to read the file. If you wish to set this to a string instead (not recommended since it will be placed world-readable in the Nix store), you can use the APP_SECRET option.";
      default     = null;
    };

    tracker_script_name = lib.mkOption {
      type        = lib.types.str;
      description = "Allows you to assign a custom name to the tracker script different from the default script.js.";
      default     = [];
    };

    collect_api_endpoint = lib.mkOption {
      type        = lib.types.str;
      description = "Allows you to send metrics to a location different than the default /api/send.";
      default     = null;
    };

    database_url = lib.mkOption {
      type        = lib.types.str;
      description = "url for database";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = with pkgs; [
      umami
    ];

    services.umami = {
      enable  = true;
      package = pkgs.umami;

      createPostgresqlDatabase = cfg.create_postgresql_database;

      settings = {
        PORT     = cfg.port;
        HOSTNAME = cfg.hostname;

        DISABLE_UPDATES   = true;
        DISABLE_TELEMETRY = true;

        BASE_PATH            = cfg.base_path;
        DATABASE_URL_FILE    = cfg.database_url_file;
        APP_SECRET_FILE      = cfg.app_secret_file;
        TRACKER_SCRIPT_NAME  = cfg.tracker_script_name;
        COLLECT_API_ENDPOINT = cfg.collect_api_endpoint;
        DATABASE_URL         = cfg.database_url;
      };
    };
  };

  services.nginx.virtualHosts."umami.${environment_domain}" = {
    enableACME = true;
    forceSSL = true;
    locations = {
      "/" = {
        proxyPass = "http://127.0.0.1:3000";
      };
    };
  };
}
