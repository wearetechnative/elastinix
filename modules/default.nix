flake: { config, lib, pkgs, ... }:

{
  imports = [
  ]
    ++
    map (n: "${./programs}/${n}") (builtins.attrNames (builtins.readDir ./programs));
}
