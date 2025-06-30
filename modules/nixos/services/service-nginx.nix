{ pkgs, config, lib, ... }:

{
  options.elastinix.services.nginx.enable = lib.mkEnableOption "enable std nginx";

  config = lib.mkIf config.elastinix.services.nginx.enable {
    security.acme = {
      acceptTerms = true;
      defaults.email = "sysadmin@technative.eu";
    };

    services.nginx = {
      enable = true;
      recommendedGzipSettings = true;
      recommendedOptimisation = true;
      recommendedProxySettings = true;
      recommendedTlsSettings = true;
      clientMaxBodySize = "25m";
    };
  };
}
