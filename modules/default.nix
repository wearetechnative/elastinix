flake: { config, lib, pkgs, ... }:

{
  imports = []
    ++
    map (n: "${./modules/programs}/${n}") (builtins.attrNames (builtins.readDir ./modules/programs));
}
