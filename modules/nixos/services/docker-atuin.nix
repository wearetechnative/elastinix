{ config, pkgs, tfvars, lib, ... }:

let
  cfg = config.elastinix.services.atuin;
  environment_domain = tfvars.environment_domain;
  networkName = "atuin";
in
  {

  options.elastinix.services.atuin = {
    enable = lib.mkEnableOption "enable Atuin";

    forward_port = lib.mkOption {
      type = lib.types.str;
      default = "8888";
      description = "The port that should be used";
    };

    database_host = lib.mkOption {
      type = lib.types.str;
      description = "";
    };

    version = lib.mkOption {
      type = lib.types.str;
      default = "18.3.0";
      description = "";
    };
  };

  config = lib.mkIf cfg.enable{
    system.activationScripts.AtuinNetwork =
      let
        backend = config.virtualisation.oci-containers.backend;
        backendBin = "${pkgs.${backend}}/bin/${backend}";
      in
        ''
        ${backendBin} network inspect ${networkName} >/dev/null 2>&1 || \
        ${backendBin} network create --driver bridge ${networkName}
      '';

    ## TODO DATABASE NEED TO ALREADY EXIST
    ## TODO SET ADMIN USER
    virtualisation.oci-containers.containers."atuin" =
      let

        PG_DATABASE_HOST = "${cfg.database_host}";

      in
        {
        image = "ghcr.io/atuinsh/atuin:v${cfg.version}";
        ports = [ "${cfg.forward_port}:8888" ];
        environment = {

          PORT = "8888";
          ATUIN_HOST = "0.0.0.0";
          ATUIN_OPEN_REGISTRATION = "true";
          ATUIN_DB_URI = "postgres://atuin:atuin@${cfg.database_host}/atuin";

        };
        dependsOn = [ ];
        volumes = [
        ];
        #extraOptions = [ "--network=${networkName}" ];
        cmd = ["server" "start"];
      };

    services.nginx.virtualHosts."atuin.${environment_domain}" = {
      enableACME = true;
      forceSSL = true;
      locations = {
        "/" = {
          proxyPass = "http://127.0.0.1:${cfg.forward_port}";
        };
      };
    };
  };
}
