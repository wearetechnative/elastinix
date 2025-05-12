{
  description = "Elastix, getting Nix to the Cloud";
  inputs = {

    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.05";

    #nixpkgs-oldterraform.url = "github:NixOS/nixpkgs/nixos-23.05";

    nixos-generators.url = "github:nix-community/nixos-generators/7c60ba4bc8d6aa2ba3e5b0f6ceb9fc07bc261565";
    nixos-generators.inputs.nixpkgs.follows = "nixpkgs";

    agenix.url = "github:ryantm/agenix";
  };

  outputs = {
    self,
    nixpkgs,
    nixos-generators,
    agenix
    # , nixpkgs-oldterraform
    }:
    let
      elastinixModule = { config, pkgs, ... }:
        let
          system = pkgs.stdenv.hostPlatform.system;

        in {

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

    in
      {
      nixosModules.default = elastinixModule;

      lib = import ./lib { inherit nixpkgs; inherit elastinixModule; inherit nixos-generators; };
    };
}
