{ config, lib, pkgs, ... }:

{
  options.elastinix.services.nebula = {
    enable = lib.mkEnableOption "Nebula";
    keyPath = lib.mkOption {
      type = lib.types.path;
      description = "path to key";
    };

    caCertPath = lib.mkOption {
      type = lib.types.path;
      description = "path to ca certificate";
    };
    certPath = lib.mkOption {
      type = lib.types.path;
      description = "path to certificate";
    };
    isLighthouse = lib.mkOption {
      type = lib.types.bool;
      description = "Enable/disable lighthouse";
    };
  };

  config = lib.mkIf config.elastinix.services.nebula.enable {
    environment.systemPackages = with pkgs; [ nebula ];
    services.nebula.networks.mesh = {
      enable = true;
      isLighthouse = config.elastinix.services.nebula.isLighthouse;
      cert = config.elastinix.services.nebula.certPath;
      key = config.elastinix.services.nebula.keyPath;
      ca = config.elastinix.services.nebula.caCertPath;
    };

    networking.firewall = {
      allowedUDPPorts = [ 4242 ];
    };
  };
}
