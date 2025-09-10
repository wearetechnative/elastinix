{ lib, config, ... }:
let
  cfg = config.elastinix.services.traefik;
in
{
  options.elastinix.services.traefik = {

    enable = lib.mkEnableOption "Modern reverse proxy load balancer.";

    email = lib.mkOption {
      type = lib.types.str;
      description = "The letscencrypt acme email";
    };
    storage = lib.mkOption {
      type = lib.types.str;
      description = "The letsencrypt acme storage location";
    };
  };

  config = lib.mkIf cfg.enable {

    services.traefik = {
      enable = true;

      dynamicConfigOptions = {
        http = {
          middlewares.redirect-to-https.redirectscheme = {
            scheme = "https";
            permanent = true;
          };
        };
      };

      staticConfigOptions = {

        api = {
          dashboard = true;
        };

        certificatesResolvers = {
          letsencrypt.acme = {
            email = cfg.email;
            storage = cfg.storage;
            tlsChallenge = true;
          };
        };

        entryPoints = {
          web.address = ":80";
          websecure.address = ":443";
        };
      };
    };
  };
}

