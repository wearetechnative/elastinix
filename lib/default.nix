{nixpkgs, elastinixModule, nixos-generators, ...}:
{
  tf_command = import ./tf_command.nix {
    inherit nixpkgs;
    inherit elastinixModule;
    inherit nixos-generators;
  };
}

