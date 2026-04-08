{ lib, config, inputs, pkgs, tfvars, ... }:

let
  cfg = config.elastinix.services.pontifex;
  system = pkgs.stdenv.hostPlatform.system;
  environment_domain = tfvars.environment_domain;
in {
  options.elastinix.services.pontifex = {

    enable = lib.mkEnableOption "Pontifex";

    envFile = lib.mkOption {
      type = lib.types.str;
      description = "The environment file for Pontifex";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      inputs.pontifex.packages.${system}.pontifex
    ];
    services.pontifex = {
      enable = true;
      envFile = cfg.envFile;
    };

    services.nginx.virtualHosts."pontifex.${environment_domain}" = {
      enableACME = true;
      forceSSL = true;
      locations = {
        "/" = {
          proxyPass = "http://127.0.0.1:4000";
        };
      };
    };
  };
}

