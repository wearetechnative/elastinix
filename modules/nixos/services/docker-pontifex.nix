{lib, config, pontifex, ... }:
let
  cfg = config.elastinix.services.pontifex;
in
  {
  options.elastinix.services.pontifex = {
    enable = lib.mkEnableOption "enable pontifex";

    environment_file = lib.mkOption {
      type = lib.types.str;
      description = "";
    };
  };

  config = lib.mkIf cfg.enable{
    environment.systemPackages = [
      pontifex.packages."x86_64-linux".croctalk
      pontifex.nixosModules."x86_64-linux".croctalk
    ];

    #    services.pontifex = {
    #      enable = true;
    #      EnvironmentFile = cfg.environment_file;
    #    };
  };
}
