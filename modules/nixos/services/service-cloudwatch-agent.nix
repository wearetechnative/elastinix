{ config, lib, tfvars, ... }:
let
  cfg = config.elastinix.services.cloudwatch-agent;
  infra_environment = tfvars.infra_environment;
in
  {
  options.elastinix.services.cloudwatch-agent = {

    enable = lib.mkEnableOption "Cloudwatch agent";

    config = lib.mkOption {
      type = lib.types.str;
      default = "cloudwatch_config_${infra_environment}";
      description = "Cloudwatch config name";
    };

    configPath = lib.mkOption {
      type = lib.types.str;
      default = "${toString ./.}/../secrets/cloudwatch_config_${infra_environment}.age";
      description = "Cloudwatch config location";
    };
  };

  config = lib.mkIf cfg.enable {

    services.amazon-cloudwatch-agent = {
      enable = true;
      mode = "ec2";

      configuration = {
        agent = {
          metrics_collection_interval = 60;
          run_as_user = "root";
        };
        metrics.metrics_collected = {
          disk = {
            measurement = [ "disk_used_percent" ];
            metrics_collection_interval = 60;
          };
          mem = {
            measurement = [ "mem_used_percent" ];
            metrics_collection_interval = 60;
          };
          net = {
            measurement = [
              "bytes_sent" "bytes_recv"
              "packets_sent" "packets_recv"
            ];
            metrics_collection_interval = 60;
            resources = [ "*" ];
          };
          swap = {
            measurement = [ "swap_used_percent" ];
            metrics_collection_interval = 60;
          };
        };
      };
    }
      // lib.optionalAttrs (builtins.pathExists cfg.configPath) {
        configurationFile = config.age.secrets.${cfg.config}.path;
      };
  };
}
