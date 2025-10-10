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
        {
          amazonImage.name = "nixos_image";
          #amazonImage.sizeMB = 16 * 1024;
          virtualisation.diskSize = 8 * 1024;
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