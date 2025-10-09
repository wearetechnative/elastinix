{ lib, config, pkgs, tfvars, ... }:

let
  cfg = config.elastinix.services.monitoring;
  infra_environment = tfvars.infra_environment;

  bin = {
    systemctl = "${pkgs.systemd}/bin/systemctl";
    logger = "${pkgs.logger}/bin/logger";
  };

in {
  options.elastinix.services.monitoring = {
    enable = lib.mkEnableOption "Systemd Monitoring";

    services = lib.mkOption {
      type = with lib.types; listOf str;
      default = [ ];
      description = "List of systemd services to monitor.";
    };
  };

  config = lib.mkIf cfg.enable {

    # Create logrotate config per monitored service
    services.logrotate.settings = {
      header.dateext = true;

      # Dynamically generate per-service rotation entries
      "monitored-services" = {
        files = map (s: "/var/log/${s}-monitoring.log") cfg.services;
        frequency = "daily";
        rotate = 7;
      };
    };

    # Define timers + services for each monitored service
    systemd.timers = lib.genAttrs cfg.services (s: {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "*:5/10";
        Unit = "${infra_environment}-${s}-monitoring.service";
      };
    });

    systemd.services = lib.genAttrs cfg.services (s: {
      serviceConfig.Type = "oneshot";
      wantedBy = [ "multi-user.target" ];
      script = ''
        exec > >(tee -a /var/log/${s}-monitoring.log | while read line; do ${bin.logger} -t ${infra_environment}-${s}-monitoring.* "$line"; done) 2>&1

        active=$(${bin.systemctl} status ${s}.service | grep -o 'Active: active' || echo "inactive")
        success="Active: active"

        echo "---- Timestamp: $(date)"
        if [ "$active" = "$success" ]; then
          echo "---- Service '${s}' is running successfully ----"
        else
          echo "---- Service '${s}' encountered issues ----"
        fi
      '';
    });
  };
}
