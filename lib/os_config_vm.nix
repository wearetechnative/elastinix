{inputs}:
  { nixpkgs, targetSystem, machineConfig, varsfile, rootAuthorizedKeys ? [],... }:

inputs.nixos-generators.nixosGenerate {
  system = targetSystem;

  pkgs = import nixpkgs { system = targetSystem; config.allowUnfree = true; };
  format = "qcow";
  modules =
    let
      tfvars = if varsfile == ""
        then
        {}
      else
        builtins.fromJSON (builtins.readFile varsfile);
    in

      [
        {
          _module.args.nixpkgs = nixpkgs;
          _module.args.tfvars = tfvars;
          _module.args.inputs = inputs;
          _module.args.targetSystem = targetSystem;
        }
        {
          virtualisation.diskSize = 8 * 1024;

          fileSystems."/" = {
            device = "/dev/disk/by-label/nixos";
            fsType = "ext4";
            autoResize = true;
          };

          boot.growPartition = true;
          boot.kernelParams = [ "console=ttyS0" ];
          boot.loader.grub.device = "/dev/vda";
          boot.loader.timeout = 0;

          users.extraUsers.root.password = "";
        }

        "${nixpkgs}/nixos/modules/profiles/qemu-guest.nix"
        #"${nixpkgs}/nixos/modules/virtualisation/amazon-image.nix"
        (import ../modules/nixos/bootstrap/base-conf.nix rootAuthorizedKeys)

        inputs.agenix.nixosModules.default
        inputs.nixos-healthchecks.nixosModules.default
        inputs.slack2zammad.nixosModules.slack2zammad

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
}
