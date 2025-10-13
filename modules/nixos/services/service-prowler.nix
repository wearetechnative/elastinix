{ pkgs, config, lib, ... }:
{
  environment.systemPackages = [
        pkgs.prowler
        pkgs.awscli2
    ];
  networking.firewall.allowedTCPPorts = [11666];

}