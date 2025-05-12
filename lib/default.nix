{nixpkgs, elastinixModule, nixos-generators, nixpkgs-terraform-1-5-3, ...}:
{
  tf_command = import ./tf_command.nix {
    inherit nixpkgs;
    inherit elastinixModule;
    inherit nixos-generators;
    inherit nixpkgs-terraform-1-5-3;
  };

  forAllSystems = nixpkgs.lib.genAttrs [ "x86_64-linux" "x86_64-darwin" "aarch64-linux" "aarch64-darwin" ];

}

