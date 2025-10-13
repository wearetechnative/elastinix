{config, lib, ... }:

let
  cfg = config.elastinix.services.matterbridge;
in

  {
  options.elastinix.services.matterbridge = {

    enable = lib.mkEnableOption "matterbridge";

    environment_file = lib.mkOption {
      type = lib.types.str;
      description = "The environment variables for matterbridge";
    };
  };

  config = lib.mkIf cfg.enable {

    nixpkgs.overlays = [
      (final: prev: {
        matterbridge = prev.buildGoModule rec {
          pname = "matterbridge";
          version = "bb64979fca9eb41880ef8e056a08bb0e458383bb";
          src = prev.fetchgit {
            url = "https://github.com/TechNative-B-V/matterbridge.git";
            rev = "${version}";
            hash = "sha256-3KA3agTOianmzTv24d7o9Xb45i9YSuqNU0VM45MmX6Q=";
          };
          vendorHash = null;
        };
      })];

    services.matterbridge = {
      enable = true;
      configPath = cfg.environment_file;
    };
  };
}
