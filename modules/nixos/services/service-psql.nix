{config, lib, pkgs, ... }:
let
  cfg = config.elastinix.services.postgresql;
in
  {
  options.elastinix.services.postgresql = {

    enable = lib.mkEnableOption "postgresql Database";

    port = lib.mkOption {
      type = lib.types.int;
      default = 5432;
      description = "The port where postgres will be accessible from";
    };

    initial_script = lib.mkOption {
      type = lib.types.str;
      description = "The initial script for postgres";
    };

    data_dir = lib.mkOption {
      type = lib.types.str;
      default = "/data/postgresql";
      description = "The datadir location for postgres";
    };
  };

  config = lib.mkIf cfg.enable {

    services.postgresql = {
      enable = true;
      dataDir = cfg.data_dir;
      enableTCPIP = true;
      ensureUsers = [ { name = "postgres"; } ];
      settings = {
        port = cfg.port;
        ssl = false;
      };
      authentication = ''
    #type database DBuser origin-address auth-method
    # ipv4 from everywhere (including dockers) firewall and SG blocks real outside connections
      host  all      all     0.0.0.0/0      scram-sha-256
    # ipv6 from localhost
      host all       all     ::1/128        scram-sha-256
      '';
      initialScript = cfg.initial_script;
    };
  };
}
