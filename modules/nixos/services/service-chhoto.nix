{ lib, config, tfvars, ... }:
let
  cfg = config.elastinix.services.chhoto;
  environment_domain = tfvars.environment_domain;
in
{
  options.elastinix.services.chhoto = {

    enable = lib.mkEnableOption "Chhoto URL shortener";

    environmentFiles = lib.mkOption {
      type = lib.types.listOf lib.types.path;
      default = [];
      description = "Environment files for secrets (password, API key).";
    };

    port = lib.mkOption {
      type = lib.types.port;
      description = "Port for the chhoto-url server.";
    };

    siteUrl = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "External URL where chhoto-url is publicly accessible.";
    };
  };

  config = lib.mkIf cfg.enable {
    services.chhoto-url = {
      enable = true;
      environmentFiles = cfg.environmentFiles;
      settings = {
        port = cfg.port;
        site_url = "https://chhoto-url.${environment_domain}";
        disable_frontend = false;
      };
    };

    services.nginx.virtualHosts."chhoto-url.${environment_domain}" = {
      enableACME = true;
      forceSSL = true;
      locations = {
        "/" = {
          proxyPass = "http://127.0.0.1:${builtins.toString cfg.port}";
        };
      };
    };
  };
}
