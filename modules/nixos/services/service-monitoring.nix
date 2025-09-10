serviceToManage: { lib, config, pkgs, tfvarsfile, ... }:

let
  tfvarsContent = builtins.readFile tfvarsfile;
  tfvars = builtins.fromJSON tfvarsContent;
  infra_environment = tfvars.infra_environment;
  monitoring_service = serviceToManage;

  bin.systemctl = "${pkgs.systemd}/bin/systemctl";
  bin.logger    = "${pkgs.logger}/bin/logger";


in {
    services.logrotate.settings = {
      header = {
        dateext = true;
      };
      "multiple paths" = {
        files = [
          "/var/log/${monitoring_service}-monitoring.log"
        ];
        frequency = "daily";
        rotate = 7;
      };
    };

    systemd.timers."${infra_environment}-${monitoring_service}-monitoring" = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar="*:5/10";
        Unit = "${infra_environment}-${monitoring_service}-monitoring.service";
      };
    };


    systemd.services."${infra_environment}-${monitoring_service}-monitoring" =
    {
      serviceConfig.Type = "oneshot";
      wantedBy = [ "multi-user.target" ];
      script = ''
        exec > >(tee -a /var/log/${monitoring_service}-monitoring.log | while read line; do ${bin.logger} -t ${infra_environment}-${monitoring_service}-monitoring.* "$line"; done) 2>&1

        active=$(${bin.systemctl} status ${monitoring_service}.service | grep -o 'Active: active' || echo "inactive")

        succes="Active: active"

        if [ "$active" = "$succes" ];
          then
            echo "---- Timestamp: $(date)"
            echo "---- Service run successfully ----"
          else
            echo "---- Timestamp: $(date)"
            echo "---- Service run with errors ----"
        fi
      '';
    };
}
