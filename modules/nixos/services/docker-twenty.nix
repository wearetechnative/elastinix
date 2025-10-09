{ lib, config, pkgs, tfvars, ... }:

let
  cfg = config.elastinix.services.twenty;
  networkName = "twenty-net";
  environment_domain = tfvars.environment_domain;
in
  {
  options.elastinix.services.twenty = {

    enable = lib.mkEnableOption "Twenty CRM";

    version = lib.mkOption {
      type = lib.types.str;
      description = "Twenty version";
    };

    forward_port = lib.mkOption {
      type = lib.types.str;
      default = "8080";
      description = "The port that should be used";
    };

    # Server
    server_environment_file = lib.mkOption {
      type = lib.types.str;
      description = "The environment variables for twenty server";
    };

    # Worker
    worker_environment_file = lib.mkOption {
      type = lib.types.str;
      description = "The environment variables for twenty worker";
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

    ## TODO DATABASE NEED TO ALREADY EXIST
    virtualisation.oci-containers.containers."twenty" =
      {
        image = "twentycrm/twenty:${cfg.version}";
        ports = [ "${cfg.forward_port}:3000" ];
        environmentFiles = [ cfg.server_environment_file ];
        dependsOn = [ ];
        volumes = [
          "server-local-data:/app/packages/twenty-server/.local-storage"
          "docker-data:/app/docker-data"
        ];
        extraOptions = [
          "--network=${networkName}"
          "--add-host=host.docker.internal:host-gateway"
        ];
      };

    virtualisation.oci-containers.containers."twenty-worker" =
      {
        image = "twentycrm/twenty:${cfg.version}";
        environmentFiles = [ cfg.worker_environment_file ];
        dependsOn = [ ];
        volumes = [
          "server-local-data:/app/packages/twenty-server/.local-storage"
          "docker-data:/app/docker-data"
        ];
        cmd = [
          "yarn"
          "worker:prod"
        ];
        extraOptions = [
          "--network=${networkName}"
          "--add-host=host.docker.internal:host-gateway"
        ];
      };

    services.nginx.virtualHosts."twenty.${environment_domain}" = {
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
