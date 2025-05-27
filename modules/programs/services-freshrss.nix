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
    services.freshrss = {
      enable = true;
      package = pkgs.freshrss;
      user = "freshrss";
      baseUrl = cfg.baseurl;
      virtualHost = "freshrss";
      passwordFile = cfg.passwordfile;

      database = {
        name = "freshrss";
        host = cfg.database_host;
        user = "freshrss";
        passFile = cfg.database_passfile;
        type = "pgsql";
        port = 3306;
        tableprefix = "freshrss";
      };
    };
  };
}
