{ lib, config, pkgs, tfvarsfile, ... }:

let
  cfg = config.elastinix.services.twenty-redis;
  networkName = "psql-twenty-net";
in
  {
  options.elastinix.services.twenty-redis = {

    enable = lib.mkEnableOption "Twenty redis";

    version = lib.mkOption {
      type = lib.types.str;
      default = "latest";
      description = "Twenty redis version";
    };

    host = lib.mkOption {
      type = lib.types.str;
      default = "redis";
      description = "The hostname to connect with redis";
    };

    forward_port = lib.mkOption {
      type = lib.types.str;
      default = "6379";
      description = "The port that should be used";
    };

    data_dir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/redis/data";
      description = "The datadir location for twenty redis";
    };

    extra_options = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "Extra cmd options to pass";
    };
  };

  config = lib.mkIf cfg.enable {

    system.activationScripts.TwentyNetwork =
      let
        backend = config.virtualisation.oci-containers.backend;
        backendBin = "${pkgs.${backend}}/bin/${backend}";
      in
        ''
        ${backendBin} network inspect ${networkName} >/dev/null 2>&1 || \
        ${backendBin} network create --driver bridge ${networkName}
      '';

    virtualisation.oci-containers.containers."redis" =
      {
        image = "redis:${cfg.version}";
        ports = [ "${cfg.forward_port}:6379" ];
        environment = {
          REDIS_HOST="${cfg.host}";
        };
        dependsOn = [ ];
        volumes = [
          "redis:${cfg.data_dir}"
        ];
        extraOptions = [ "--network=${networkName}" ];
        cmd = ["--maxmemory-policy" "noeviction" "--appendonly" "yes"];
      };
  };
}
