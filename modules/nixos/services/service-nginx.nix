{ config, lib, pkgs, inputs, modulesPath, ... }:

{
  disabledModules = [ (modulesPath + "/services/web-servers/nginx/default.nix") ];

  imports = [ "${inputs.nixpkgs-nginx}/nixos/modules/services/web-servers/nginx/default.nix" ];

  options.elastinix.services.nginx.enable = lib.mkEnableOption "enable std nginx";

  config = lib.mkMerge [
    {
      nixpkgs.overlays = [(final: prev: {
        inherit (inputs.nixpkgs-nginx.legacyPackages.${prev.stdenv.hostPlatform.system}) nginxStable;
      })];
    }
    (lib.mkIf config.elastinix.services.nginx.enable {
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
    })
  ];
}
