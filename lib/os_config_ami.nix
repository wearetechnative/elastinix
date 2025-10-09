{inputs, nixpkgs}:
  targetSystem: rootAuthorizedKeys:

inputs.nixos-generators.nixosGenerate {
  system = targetSystem;
  pkgs = import nixpkgs { system = targetSystem; config.allowUnfree = true; };
  format = "amazon";
  modules = [

        {
          _module.args.nixpkgs = nixpkgs;
          _module.args.targetSystem = targetSystem;
        }

        # "${nixpkgs}/nixos/modules/virtualisation/amazon-image.nix"
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

  ];

}