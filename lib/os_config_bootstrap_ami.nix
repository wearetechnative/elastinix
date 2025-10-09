{ inputs }:
  { nixpkgs, targetSystem, machineConfig, varsfile, rootAuthorizedKeys ? [],... } :
let

  tfvars = if varsfile == ""
    then
      {}
    else
      builtins.fromJSON (builtins.readFile varsfile);

  bootstrap_img_full = (nixpkgs.lib.nixosSystem {
    system = targetSystem;
    specialArgs = {
      inherit tfvars;
      ec2orAmi = "ami";
    };
    modules =
      [

        {
          _module.args.nixpkgs = nixpkgs;
          _module.args.targetSystem = targetSystem;
        }

        "${nixpkgs}/nixos/modules/virtualisation/amazon-image.nix"
        (import ../modules/nixos/bootstrap/base-conf.nix rootAuthorizedKeys)

        inputs.agenix.nixosModules.default
        inputs.nixos-healthchecks.nixosModules.default

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

  });
in
  "${bootstrap_img_full}/nixos_image.vhd"
