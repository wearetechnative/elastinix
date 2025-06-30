{ pkgs, config, lib, ... }:

{
  options.elastinix.services.locate.enable = lib.mkEnableOption "enable locate service";

  config = lib.mkIf config.elastinix.services.locate.enable {
    services = {
      locate.enable = true;
      locate.package = pkgs.mlocate;
      locate.localuser = null;
    };
  };

}
