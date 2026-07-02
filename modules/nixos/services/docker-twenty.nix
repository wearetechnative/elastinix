{ lib, config, pkgs, tfvars, ... }:

let
  cfg = config.elastinix.services.twenty;
  networkName = "twenty-net";
  environment_domain = tfvars.environment_domain;
in {
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

    default_subdomain = lib.mkOption {
      type = lib.types.str;
      default = "app";
      description = ''
        Twenty's DEFAULT_SUBDOMAIN in multi-workspace mode.
      '';
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
    system.activationScripts.TwentyNetwork = let
      backend = config.virtualisation.oci-containers.backend;
      backendBin = "${pkgs.${backend}}/bin/${backend}";
    in ''
      ${backendBin} network inspect ${networkName} >/dev/null 2>&1 || \
      ${backendBin} network create --driver bridge ${networkName}
    '';

    virtualisation.oci-containers.containers."twenty" = {
      image = "twentycrm/twenty:${cfg.version}";
      ports = [ "${cfg.forward_port}:3000" ];
      environment.DEFAULT_SUBDOMAIN = cfg.default_subdomain;
      environmentFiles = [ cfg.server_environment_file ];
      dependsOn = [ ];
      volumes = [
        "server-local-data:/app/packages/twenty-server/.local-storage"
        "docker-data:/app/docker-data"
      ];
      extraOptions = [
        "--network=${networkName}"
        "--add-host=host.docker.internal:host-gateway"
        "--health-cmd=curl --fail http://localhost:3000/healthz || exit 1"
        "--health-interval=30s"
        "--health-timeout=10s"
        "--health-retries=5"
        "--health-start-period=60s"
      ];
    };

    virtualisation.oci-containers.containers."twenty-worker" = {
      image = "twentycrm/twenty:${cfg.version}";
      environment.DEFAULT_SUBDOMAIN = cfg.default_subdomain;
      environmentFiles = [ cfg.worker_environment_file ];
      dependsOn = [ "twenty" ];
      volumes = [
        "server-local-data:/app/packages/twenty-server/.local-storage"
        "docker-data:/app/docker-data"
      ];
      cmd = [ "yarn" "worker:prod" ];
      extraOptions = [
        "--network=${networkName}"
        "--add-host=host.docker.internal:host-gateway"
      ];
    };

    security.acme.certs."twenty.${environment_domain}" = {
      domain = "*.twenty.${environment_domain}";
      extraDomainNames = [ "twenty.${environment_domain}" ];
      dnsProvider = "route53";
      dnsResolver = "1.1.1.1:53";
      group = "nginx";
    };

    systemd.services."acme-order-renew-twenty.${environment_domain}".environment = {
      AWS_REGION = "eu-central-1";
    };

    services.nginx.virtualHosts."twenty.${environment_domain}" = {
      useACMEHost = "twenty.${environment_domain}";
      forceSSL = true;
      extraConfig = ''
        client_max_body_size 50M;
      '';
      locations = {
        "/" = {
          proxyPass = "http://127.0.0.1:${cfg.forward_port}";
          proxyWebsockets = true;
          extraConfig = ''
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_buffering off;
            proxy_read_timeout 86400;
          '';
        };
      };
    };

    services.nginx.virtualHosts."*.twenty.${environment_domain}" = {
      useACMEHost = "twenty.${environment_domain}";
      forceSSL = true;
      extraConfig = ''
        client_max_body_size 50M;
      '';
      locations = {
        "/" = {
          proxyPass = "http://127.0.0.1:${cfg.forward_port}";
          proxyWebsockets = true;
          extraConfig = ''
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_buffering off;
            proxy_read_timeout 86400;
          '';
        };
      };
    };
  };
}
