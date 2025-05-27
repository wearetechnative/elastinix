{config, pkgs, lib, ...}:

let
  cfg = config.elastinix.programs.freshrss;
in {
  options.elastinix.programs.freshrss = {
    enable = lib.mkEnableOption "FreshRSS RSS reader";
    database_passfile = lib.mkOption {
      type = lib.types.str;
      description = "Password for database user";
    };
    database_host = lib.mkOption {
      type = lib.types.str;
      description = "Hostname of the database";
    };
    baseurl = lib.mkOption {
      type = lib.types.str;
      description = "Domain name";
    };
    passwordfile = lib.mkOption {
      type = lib.types.str;
      description = "Password for login user freshrss";
    };
  };

  config = lib.mkIf cfg.enable {
    security.acme = {
      acceptTerms = true;
      defaults.email = "sysadmin@technative.eu";
    };

    services.nginx = {
      enable = true;
      recommendedGzipSettings = true;
      recommendedOptimisation = true;
      recommendedProxySettings = true;
      recommendedTlsSettings = true;
      clientMaxBodySize = "25m";
    };

    services.nginx.virtualHosts."${cfg.baseurl}" = {
      enableACME = true;
      forceSSL = true;
      locations = {
        "/" = {
          proxyPass = "http://127.0.0.1:80";
        };
      };
    };


    services.freshrss = {
      enable = true;
      package = pkgs.freshrss;
      user = "freshrss";
      baseUrl = "https://${cfg.baseurl}";
      virtualHost = cfg.baseurl;
      passwordFile = cfg.passwordfile;
      dataDir = "/var/lib/freshrss";

      database = {
        name = "freshrss";
        host = cfg.database_host;
        user = "freshrss";
        passFile = cfg.database_passfile;
        type = "pgsql";
        port = 5432;
      };
    };
  };
}
