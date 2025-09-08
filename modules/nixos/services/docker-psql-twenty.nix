{ lib, config, pkgs, ... }:

let
  cfg = config.elastinix.services.twenty-psql;
  networkName = "psql-twenty-net";
in
  {
  options.elastinix.services.twenty-psql = {

    enable = lib.mkEnableOption "Twenty postgresql";

    version = lib.mkOption {
      type = lib.types.str;
      default = "16";
      description = "Twenty postgresql version";
    };

    environment_file = lib.mkOption {
      type = lib.types.str;
      description = "The environment variables for twenty postgresql";
    };

    forward_port = lib.mkOption {
      type = lib.types.str;
      default = "5433";
      description = "The port that should be used";
    };

    data_dir = lib.mkOption {
      type = lib.types.str;
      default = "/data/postgresql-twenty";
      description = "The datadir location for twenty postgres";
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

    virtualisation.oci-containers.containers."twenty-psql" =
      {
        image = "bitnami/postgresql:${cfg.version}";
        ports = [ "${cfg.forward_port}:5432" ];
        environmentFiles = [ cfg.environment_file ];
        dependsOn = [ ];
        volumes = [
          "db-data:${cfg.data_dir}"
        ];
        extraOptions = [ "--network=${networkName}" ];
      };

    systemd.services."docker-twenty-psql".serviceConfig.ExecStartPre = [
      "${pkgs.bash}/bin/bash -c 'chown -R 71:postgres ${cfg.data_dir}'"
    ];
  };
}
