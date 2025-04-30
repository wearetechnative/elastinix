{
  description = "Elastix, getting Nix to the Cloud";
  inputs = {

    elNixpkgs.url = "github:NixOS/nixpkgs/nixos-24.05";
    #nixpkgs-oldterraform.url = "github:NixOS/nixpkgs/nixos-23.05";
    nixos-generators.url = "github:nix-community/nixos-generators";
    nixos-generators.inputs.nixpkgs.follows = "elNixpkgs";
    agenix.url = "github:ryantm/agenix";
  };

  outputs = {
    self,
    elNixpkgs,
    nixos-generators,
    agenix
    # , nixpkgs-oldterraform
    }:
    {
      nixosModules = {
        default = { config, pkgs, ... }:
          let
            system = pkgs.stdenv.hostPlatform.system;

          in{

            imports = [
              {
                environment.systemPackages = [ agenix.packages."${system}".agenix ];
              }
              agenix.nixosModules.default
            ] ++
              map (n: "${./modules/programs}/${n}") (builtins.attrNames (builtins.readDir ./modules/programs));

            options = {};
            config = {};
          };

        #xx = import ./modules self;

      };

      lib = import ./lib {inherit nixos-generators; inherit elNixpkgs;};
    };
}
