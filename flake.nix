{
  description = "Elastix, getting Nix to the Cloud";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.05";

    nixpkgs-terraform-1-5-3.url = "github:NixOS/nixpkgs/nixos-23.05";

    nixos-generators.url = "github:nix-community/nixos-generators/7c60ba4bc8d6aa2ba3e5b0f6ceb9fc07bc261565";
    nixos-generators.inputs.nixpkgs.follows = "nixpkgs";

    import-tree.url = "github:vic/import-tree";

    nixos-healthchecks.url = "github:mrvandalo/nixos-healthchecks";

    agenix.url = "github:ryantm/agenix";

    flake-parts.url = "github:hercules-ci/flake-parts";
    devshell.url = "github:numtide/devshell";
  };

  outputs = inputs@{ flake-parts, nixpkgs, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {

      imports = [
        inputs.devshell.flakeModule
        inputs.nixos-healthchecks.flakeModule
      ];

      systems = [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" "x86_64-darwin" ];

      perSystem = _: {
        devshells.default = {};
      };

      flake = {
        lib.tf_command = import ./lib/tf_command.nix { inherit inputs nixpkgs; };
      };
    };
}
