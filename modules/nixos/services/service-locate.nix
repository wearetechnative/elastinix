{ pkgs, config, lib, ... }:

{
  options.elastinix.locate.enable = lib.mkEnableOption "enable locate service";

  config = lib.mkIf config.elastinix.locate.enable {
    services = {
      locate.enable = true;
      locate.package = pkgs.mlocate;
      locate.localuser = null;
    };
  };

}
