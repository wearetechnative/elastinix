{ lib, config, pkgs, tfvars, ... }:

let
  cfg = config.elastinix.services.solidtime;
  forwardPort = "8000";
  networkName = "solidtime-network";
  environment_domain = tfvars.environment_domain;
in
  {
  options.elastinix.services.solidtime = {

    enable = lib.mkEnableOption "Solidtime Time Tracking";

    version = lib.mkOption {
      type = lib.types.str;
      description = "Solidtime specific version";
    };

    environment_file = lib.mkOption {
      type = lib.types.str;
      description = "The environment variables for solidtime app/scheduler/queue";
    };
  };

  config = lib.mkIf cfg.enable {

    system.activationScripts.SolidTimeNetwork =
      let
        backend = config.virtualisation.oci-containers.backend;
        backendBin = "${pkgs.${backend}}/bin/${backend}";
      in
        ''
        ${backendBin} network inspect ${networkName} >/dev/null 2>&1 || \
        ${backendBin} network create --driver bridge ${networkName}
      '';

    virtualisation.oci-containers.containers."solidtime-app" =
      {
        image = "solidtime/solidtime:${cfg.version}";
        ports = [ "${forwardPort}:8000" ];
        user = "1000:1000";
        dependsOn = [ ];
        volumes = [
          "app-storage:/var/www/html/storage"
          "./data/logs:/var/www/html/storage/logs"
          "./data/app-storage:/var/www/html/storage/app"
        ];
        environment = {
          CONTAINER_MODE = "http";
        };
        environmentFiles = [ cfg.environment_file ];
        extraOptions = [
          "--network=${networkName}"
          "--add-host=host.docker.internal:host-gateway"
        ];
      };

    virtualisation.oci-containers.containers."solidtime-scheduler" =
      {
        image = "solidtime/solidtime:${cfg.version}";
        user = "1000:1000";
        dependsOn = [ ];
        volumes = [
          "app-storage:/var/www/html/storage"
          "./data/logs:/var/www/html/storage/logs"
          "./data/app-storage:/var/www/html/storage/app"
        ];
        environment = {
          CONTAINER_MODE = "scheduler";
        };
        environmentFiles = [ cfg.environment_file ];
        extraOptions = [
          "--network=${networkName}"
          "--add-host=host.docker.internal:host-gateway"
        ];
      };

    virtualisation.oci-containers.containers."solidtime-queue" =
      {
        image = "solidtime/solidtime:${cfg.version}";
        user = "1000:1000";
        dependsOn = [ ];
        volumes = [
          "app-storage:/var/www/html/storage"
          "./data/logs:/var/www/html/storage/logs"
          "./data/app-storage:/var/www/html/storage/app"
        ];
        environment = {
          CONTAINER_MODE = "worker";
          WORKER_COMMAND = "php /var/www/html/artisan queue:work";
        };
        environmentFiles = [ cfg.environment_file ];
        extraOptions = [
          "--network=${networkName}"
          "--add-host=host.docker.internal:host-gateway"
        ];
      };

    virtualisation.oci-containers.containers."gotenberg" =
      {
        image = "gotenberg/gotenberg:8";
        dependsOn = [ ];
        extraOptions = [
          "--network=${networkName}"
          "--add-host=host.docker.internal:host-gateway"
        ];
      };

    services.nginx.virtualHosts."solidtime.${environment_domain}" = {
      enableACME = true;
      forceSSL = true;
      locations = {
        "/" = {
          proxyPass = "http://127.0.0.1:${forwardPort}";
        };
      };
    };

    systemd.services."docker-solidtime-app".serviceConfig.ExecStartPre = [
      "${pkgs.bash}/bin/bash -c 'chown -R 1000:1000 /data/logs'"
      "${pkgs.bash}/bin/bash -c 'chown -R 1000:1000 /data/app-storage'"
    ];
  };
}
