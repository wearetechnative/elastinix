{ inputs }:
{
  nixpkgs,
  targetSystem,
  machineConfig,
  varsfile,
  rootAuthorizedKeys ? [ ],
  ...
}:

(nixpkgs.lib.nixosSystem {
  system = targetSystem;
  specialArgs = { inherit inputs; };
  modules =
    let
      tfvars = if varsfile == "" then { } else builtins.fromJSON (builtins.readFile varsfile);
    in
    [
      {
        _module.args = {
          inherit
            nixpkgs
            tfvars
            targetSystem
            ;
        };
      }
      {
        virtualisation.diskSize = 8 * 1024;

        fileSystems."/" = {
          device = "/dev/disk/by-label/nixos";
          fsType = "ext4";
          autoResize = true;
        };

        boot = {
          growPartition = true;
          kernelParams = [ "console=ttyS0" ];
          loader = {
            grub.device = "/dev/vda";
            timeout = 0;
          };
        };

        users.extraUsers.root.password = "";
      }

      "${nixpkgs}/nixos/modules/profiles/qemu-guest.nix"
      (import ../modules/nixos/bootstrap/base-conf.nix rootAuthorizedKeys)

      inputs.agenix.nixosModules.default
      inputs.nixos-healthchecks.nixosModules.default
      inputs.slack2zammad.nixosModules.slack2zammad
      inputs.pontifex.nixosModules.pontifex
      inputs.optscale.nixosModules.optscale-appliance

      (inputs.import-tree ../modules/nixos/programs)
      (inputs.import-tree ../modules/nixos/services)
      (inputs.import-tree ../modules/nixos/tests)

      {
        environment.systemPackages = [
          inputs.agenix.packages.${targetSystem}.agenix
        ];
      }

      machineConfig
    ];
}).config.system.build.image
