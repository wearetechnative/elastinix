{ inputs, pkgs, lib, config, ... }:

let
  cfg = config.elastinix.services.slack2zammad;
  system = pkgs.stdenv.hostPlatform.system;
in

  {
  options.elastinix.services.slack2zammad = {

    enable = lib.mkEnableOption "slack to zammad";

    environment_file = lib.mkOption {
      type = lib.types.str;
      description = "";
    };
  };

  config = lib.mkIf cfg.enable {

    environment.systemPackages = [
      inputs.slack2zammad.packages.${system}.slack2zammad
    ];

    services.slack2zammad = {
      enable  = true;
      envFile = cfg.environment_file;
    };
  };
}
