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
          version = "c4157a4d5b49fce79c80a30730dc7c404bacd663";
          src = prev.fetchgit {
            url = "https://github.com//wearetechnative/matterbridge.git";
            rev = "${version}";
            hash = "sha256-ZnNVDlrkZd/I0NWmQMZzJ3RIruH0ARoVKJ4EyYVdMiw=";
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
