{ pkgs, config, lib, ... }:
{
  environment.systemPackages = [
        pkgs.prowler
    ];
}