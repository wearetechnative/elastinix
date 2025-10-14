{ pkgs, config, lib, ... }:

{
  options.elastinix.services.prowlerDashboard.enable = lib.mkEnableOption "enable prowler dashboard service";

  config = lib.mkIf config.elastinix.services.prowlerDashboard.enable {
    environment.systemPackages = [
        pkgs.prowler
        pkgs.awscli2
    ];
    networking.firewall.allowedTCPPorts = [11666];
    systemd.services.prowlerDashboard = {
        serviceConfig.Type = "oneshot";
        wantedBy = [ "multi-user.target" ];
        script = '' HOST=0.0.0.0 prowler dashoard '';
    };
  };

}
