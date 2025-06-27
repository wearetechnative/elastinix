{inputs, nixpkgs}:
targetSystem: machineConfig: bootimgModules: tfvarsfile:
let

  liveConfig = (nixpkgs.lib.nixosSystem {
    system = targetSystem;
    specialArgs = { inherit tfvarsfile; ec2orAmi = "ec2"; };
    modules =
      #bootimgModules ++
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
          ];
        }

        machineConfig

      ];

  });

in
  liveConfig.config.system.build.toplevel
