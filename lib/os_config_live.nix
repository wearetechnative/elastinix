{ inputs }:
  { nixpkgs, targetSystem, machineConfig, varsfile, rootAuthorizedKeys ? [] } :
let

  tfvars = if varsfile == ""
    then
      {}
    else
      builtins.fromJSON (builtins.readFile varsfile);

  liveConfig = (nixpkgs.lib.nixosSystem {
    system = targetSystem;
    specialArgs = { inherit tfvars; ec2orAmi = "ec2"; };
    modules =
      [

        {elastinix.rootAuthorizedKeys = rootAuthorizedKeys;}
        "${nixpkgs}/nixos/modules/virtualisation/amazon-image.nix"
        (import ../modules/nixos/bootstrap/base-conf.nix)

        {
          imports = [

            inputs.agenix.nixosModules.default
            inputs.nixos-healthchecks.nixosModules.default

            (inputs.import-tree ../modules/nixos/programs)
            (inputs.import-tree ../modules/nixos/services)
            (inputs.import-tree ../modules/nixos/tests)
          ];

          environment.systemPackages = [
             inputs.agenix.packages.${targetSystem}.agenix
          ];
        }

        machineConfig

      ];

  });
in
  liveConfig
