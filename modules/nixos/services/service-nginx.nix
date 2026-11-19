{ config, lib, pkgs, inputs, ... }:

{
  disabledModules = [ "${inputs.nixpkgs}/nixos/modules/services/web-servers/nginx/default.nix" ];

  imports = [ "${inputs.nixpkgs-nginx}/nixos/modules/services/web-servers/nginx/default.nix" ];

  options.elastinix.services.nginx.enable = lib.mkEnableOption "enable std nginx";

  config = lib.mkIf config.elastinix.services.nginx.enable {
    nixpkgs.overlays = [(final: prev: {
      inherit (inputs.nixpkgs-nginx.legacyPackages.${prev.stdenv.hostPlatform.system}) nginx;
    })];

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
