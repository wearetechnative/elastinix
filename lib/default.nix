{nixpkgs, ...}:
{
  tf_command = import ./tf_command.nix {inherit nixpkgs;};
}

