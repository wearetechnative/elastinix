{ pkgs, config, lib, ... }:

{
  options.elastinix.services.prowlerDashboard.enable = lib.mkEnableOption "enable prowler dashboard service";

  config = lib.mkIf config.elastinix.services.prowlerDashboard.enable {
    environment.systemPackages = [
        pkgs.awscli2
        pkgs.prowler
    ];
    networking.firewall.allowedTCPPorts = [11666];
    systemd.services.prowlerDashboard = {
        serviceConfig.Type = builtins.trace "simple" "simple";
        wantedBy = [ "multi-user.target" ];
        script = '' HOST=0.0.0.0 ${pkgs.prowler}/bin/prowler dashboard '';
    };
  };

}
