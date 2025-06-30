{ inputs, self, nixpkgs }:
  targetSystem: bootimgModules: machineConfig: tfvarsfile:
let

  tfvars = if tfvarsfile == ""
    then
      {}
    else
      builtins.fromJSON (builtins.readFile tfvarsfile);

  liveConfig = (nixpkgs.lib.nixosSystem {
    system = targetSystem;
    specialArgs = { inherit tfvars; ec2orAmi = "ec2"; };
    modules =
      bootimgModules ++
      [
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
             self.packages.${targetSystem}.healthchecks
          ];
        }

        machineConfig

      ];

  });

in
  liveConfig.config.system.build.toplevel
