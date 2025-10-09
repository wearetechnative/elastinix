{ pkgs, config, lib, ... }:
let

  cfg = config.elastinix.programs.docker;

in {

  options.elastinix.programs.docker.enable = lib.mkEnableOption ''
    Docker backend
  '';

  config = lib.mkIf cfg.enable {

  virtualisation.oci-containers.backend = "docker";
  networking.dhcpcd.runHook = ''
      iface=$(${pkgs.iproute2}/bin/ip route get 8.8.8.8 | ${pkgs.gnused}/bin/sed -n 's/.*dev \([^\ ]*\) src.*/\1/p')
      ${pkgs.iproute2}/bin/ip r a 169.254.169.254/32 dev "$iface" || true
  '';
  };
}
