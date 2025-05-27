{config, pkgs, lib, ...}:

let
  cfg = config.elastinix.programs.freshrss;
in {
  options.elastinix.programs.freshrss = {
    enable = lib.mkEnableOption "FreshRSS RSS reader";
    passfile = lib.mkOption {
      type = lib.types.str;
      description = "Location of passfile";
    };
    database_host = lib.mkOption {
      type = lib.types.str;
      description = "Database hostname";
    };
    baseurl = lib.mkOption {
      type = lib.types.str;
      description = "Domain name";
    };
  };

  config = lib.mkIf cfg.enable {
    services.freshrss = {
      enable = true;
      package = pkgs.freshrss;
      user = "freshrss";
      baseUrl = cfg.baseurl;
      virtualHost = "freshrss";

      database = {
        name = "freshrss";
        host = cfg.database_host;
        user = "freshrss";
        passFile = cfg.passfile;
        type = "pgsql";
        port = 3306;
        tableprefix = "freshrss";
      };
    };
  };
}
