{
  description = "Elastix, getting Nix to the Cloud";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.05";

    #nixpkgs-unstable.url = "github:NixOS/nixpkgs/nixos-unstable";

    nixpkgs-terraform-1-5-3.url = "github:NixOS/nixpkgs/nixos-23.05";

    nixos-generators.url = "github:nix-community/nixos-generators/7c60ba4bc8d6aa2ba3e5b0f6ceb9fc07bc261565";
    nixos-generators.inputs.nixpkgs.follows = "nixpkgs";

    import-tree.url = "github:vic/import-tree";

    nixos-healthchecks.url = "github:mrvandalo/nixos-healthchecks";
    #nixos-healthchecks.inputs.nixpkgs.follows = "nixpkgs-unstable";

    agenix.url = "github:ryantm/agenix";

    flake-parts.url = "github:hercules-ci/flake-parts";
    devshell.url = "github:numtide/devshell";
  };
  outputs = inputs@{
    flake-parts,
    nixpkgs,
    #    nixpkgs-unstable,
    # agenix,
    #nixos-generators,
    #nixpkgs-terraform-1-5-3,
    #nixos-healthchecks,
    ...
    }:

    let
      ## Standard Dependencies
      elastinixModule = { config, pkgs, ... }:
        let
          system = pkgs.stdenv.hostPlatform.system;
        in {

          imports = [
            inputs.agenix.nixosModules.default
            inputs.nixos-healthchecks.nixosModules.default
            {
              environment.systemPackages = [
                inputs.agenix.packages.${system}.agenix
                #inputs.nixos-healthchecks.packages.${system}.healthchecks
              ];
            }
          ] ++ inputs.import-tree ./modules/programs;

          #options = {};
          #config = {};

        };
    in

      flake-parts.lib.mkFlake { inherit inputs; } {

        imports = [
          inputs.devshell.flakeModule
        ];

        systems = [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" "x86_64-darwin" ];

        perSystem = _: {
          devshells.default = {};
        };

        flake = {
          nixosModules.default = elastinixModule;

          lib = import ./lib { inherit inputs nixpkgs elastinixModule; };

          nixosModules.stdPrograms = { pkgs, ... }: {
            imports = [ ./flake-modules/nixos/std-programs.nix ];
          };

          #nixosConfigurations.twenty = inputs.nixpkgs.lib.nixosSystem {
          #  system = "x86_64-linux";
          #  modules = [
          #    ./modules/programs/e2e-testing.nix
          #    nixos-healthchecks.nixosModules.default
          #    {
          #      environment.systemPackages = [];
          #    }
          #  ];
          #};
        };
      };
}
