{ lib, config, pkgs, tfvars, ... }:

let
  cfg = config.elastinix.services.vaultwarden;
  environment_domain = tfvars.environment_domain;
in

  {
  options.elastinix.services.vaultwarden = {

    enable = lib.mkEnableOption "vaultwarden";

    environment_file = lib.mkOption {
      type = lib.types.str;
      description = "The environment variables for vaultwarden";
    };
  };

  config = lib.mkIf cfg.enable {
    # Vaultwarden service configuration
    services.vaultwarden = {
      enable = true;
      dbBackend = "postgresql";
      environmentFile = cfg.environment_file;
    };

    environment.systemPackages = [
      pkgs.system-sendmail
    ];

    security.acme.certs."vaultwarden.${environment_domain}" = {
      webroot = "/var/lib/acme/acme-challenge";
      group = "nginx";
    };

    systemd.services.vaultwarden.serviceConfig.ReadWritePaths = "/vaultwarden"; # needed to get systemd vaultwarden.service read outside system folders

    services.nginx.virtualHosts."vaultwarden.${environment_domain}" = {
      enableACME = true;
      forceSSL = true;
      locations = {
        "/" = {
          proxyPass = "http://127.0.0.1:8222";
        };
      };
    };
  };
}
