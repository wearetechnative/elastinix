{config, pkgs, ... }:

{
  services.journald.extraConfig = "SystemMaxUse=100M";
  services.fail2ban.enable = true;
}
