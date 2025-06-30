{ config, pkgs, tfvars, lib, ... }:

let
  cfg = config.elastinix.services.atuin;
  forwardPort = "8888";
  networkName = "atuin";
  pg_database_host = tfvars.docker_twenty_pgDatabaseName;
  domainName = tfvars.docker_atuin_domainName;
  atuin_image = tfvars.docker_atuin_dockerImage;
in
  {

  options.elastinix.services.atuin = {
    enable = lib.mkEnableOption "enable Atuin";
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

        PG_DATABASE_HOST = "${pg_database_host}";

      in
        {
        image = "${atuin_image}";
        ports = [ "${forwardPort}:8888" ];
        environment = {

          PORT = "8888";
          ATUIN_HOST = "0.0.0.0";
          ATUIN_OPEN_REGISTRATION = "true";
          ATUIN_DB_URI = "postgres://atuin:atuin@${PG_DATABASE_HOST}/atuin";

        };
        dependsOn = [ ];
        volumes = [
        ];
        #extraOptions = [ "--network=${networkName}" ];
        cmd = ["server" "start"];
      };

    services.nginx.virtualHosts."${domainName}" = {
      enableACME = true;
      forceSSL = true;
      locations = {
        "/" = {
          proxyPass = "http://127.0.0.1:${forwardPort}";
        };
      };
    };
  };
}
