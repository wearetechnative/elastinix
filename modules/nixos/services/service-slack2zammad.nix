{ lib, config, ... }:

let
  cfg = config.elastinix.services.slack2zammad;
in

  {
    #  options.elastinix.services.slack2zammad = {
    #
    #    enable = lib.mkEnableOption "slack to zammad";
    #
    #    environment_file = lib.mkOption {
    #      type = lib.types.str;
    #      description = "";
    #    };
    #  };
    #
    #  config = lib.mkIf cfg.enable {
    #
    #    services.slack2zammad = {
    #      enable  = true;
    #      envFile = cfg.environment_file;
    #    };
    #  };
}
