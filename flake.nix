{
  description = "Elastix, getting Nix to the Cloud";
  inputs = {

    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.05";
    nixpkgs-oldterraform.url = "github:NixOS/nixpkgs/nixos-23.05";
    nixos-generators.url = "github:nix-community/nixos-generators";
    nixos-generators.inputs.nixpkgs.follows = "nixpkgs";
    agenix.url = "github:ryantm/agenix";
  };

  outputs = { self, nixpkgs, nixos-generators, agenix , nixpkgs-oldterraform } :

  let
    supportedSystems = [ "x86_64-linux" "aarch64-linux" ];
    forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
    nixpkgsFor = forAllSystems (system: import nixpkgs { inherit system; config.allowUnfree = true; overlays = [  ];  });

  in {

    nixosModules = forAllSystems (system:
    let
      pkgs = nixpkgsFor.${system};
    in
    {
      default = { config, pkgs, ... }: {
        imports = [


            ];
        options = {};
        config = {};
      };

      #xx = import ./modules self;

    });

    lib = import ./lib;
  };
}
