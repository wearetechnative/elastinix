{ pkgs, config, lib, ... }:
{
  environment.systemPackages = [
        pkgs.prowler
    ];
  networking.firewall.allowedTCPPorts = [11666];

}