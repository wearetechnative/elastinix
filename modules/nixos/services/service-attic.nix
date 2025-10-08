{ lib, config, tfvars, ... }:
let
  cfg = config.elastinix.services.attic;
  environment_domain = tfvars.environment_domain;
  infra_environment = tfvars.infra_environment;
in

  {
  options.elastinix.services.attic = {

    enable = lib.mkEnableOption "Attic cache";

    environment_file = lib.mkOption {
      type = lib.types.str;
      description = "";
    };

    s3_bucket = lib.mkOption {
      type = lib.types.str;
      description = "";
    };
  };

  config = lib.mkIf cfg.enable {
    services.atticd = {
      enable = true;

      # Replace with absolute path to your credentials file
      environmentFile = cfg.environment_file;

      settings = {
        listen = "[::]:8080";
        api-endpoint = "https://attic.${environment_domain}/";

        # Data chunking
        #
        # Warning: If you change any of the values here, it will be
        # difficult to reuse existing chunks for newly-uploaded NARs
        # since the cutpoints will be different. As a result, the
        # deduplication ratio will suffer for a while after the change.
        chunking = {
          # The minimum NAR siz/tmp/attic.enve to trigger chunking
          #
          # If 0, chunking is disabled entirely for newly-uploaded NARs.
          # If 1, all NARs are chunked.
          nar-size-threshold = 64 * 1024; # 64 KiB

          # The preferred minimum size of a chunk, in bytes
          min-size = 16 * 1024; # 16 KiB

          # The preferred average size of a chunk, in bytes
          avg-size = 64 * 1024; # 64 KiB

          # The preferred maximum size of a chunk, in bytes
          max-size = 256 * 1024; # 256 KiB

        };
        storage = {
          type = "s3";
          region = "eu-central-1";
          bucket = "${cfg.s3_bucket}-${infra_environment}";
        };

      };
    };

    services.nginx.virtualHosts."attic.${environment_domain}" = {
      enableACME = true;
      forceSSL = true;

      extraConfig = ''client_max_body_size 0;'';

      locations = {
        "/" = {
          proxyPass = "http://127.0.0.1:8080";
          proxyWebsockets = true;
        };
      };
    };
  };
}
