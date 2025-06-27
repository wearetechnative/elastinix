{inputs, nixpkgs}:
  targetSystem: bootimgModules:

inputs.nixos-generators.nixosGenerate {
  system = targetSystem;
  pkgs = import nixpkgs { system = targetSystem; config.allowUnfree = true; };
  format = "amazon";
  modules = bootimgModules ++ [
    { amazonImage.name = "nixos_image"; amazonImage.sizeMB = 16 * 1024; }
  ];
}
