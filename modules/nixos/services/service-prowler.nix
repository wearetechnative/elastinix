{ pkgs, config, lib, varsfile, ... }:
let
tfvars = builtins.fromJSON (builtins.readFile varsfile);
bucket_name = tfvars.prowler_report_bucket_name;
in
{
  
  options.elastinix.services.prowlerDashboard.enable = lib.mkEnableOption "enable prowler dashboard service";

  config = lib.mkIf config.elastinix.services.prowlerDashboard.enable {
    environment.systemPackages = [
        pkgs.awscli2
        pkgs.prowler
    ];
    networking.firewall.allowedTCPPorts = [11666];
    systemd.services.prowlerDashboard = {
        serviceConfig.Type = "simple";
        wantedBy = [ "multi-user.target" ];
        script = '' 
          ${pkgs.awscli2}/bin/aws s3 cp s3://${bucket_name}/output/csv /output --recursive
          ${pkgs.awscli2}/bin/aws s3 cp s3://${bucket_name}/output/compliance /output/compliance --recursive
          HOST=0.0.0.0 ${pkgs.prowler}/bin/prowler dashboard 
        '';
    };
  };

}
