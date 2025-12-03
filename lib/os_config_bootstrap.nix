{inputs, nixpkgs}:
  targetSystem: rootAuthorizedKeys:

inputs.nixos-generators.nixosGenerate {
  system = targetSystem;
  pkgs = import nixpkgs { system = targetSystem; config.allowUnfree = true; };
  format = "amazon";
  modules = [

    #"${nixpkgs}/nixos/modules/virtualisation/amazon-image.nix"

    {
      image.baseName = "nixos_image";
      #amazonImage.name = "nixos_image";
      #amazonImage.sizeMB = 16 * 1024;
      virtualisation.diskSize = 16 * 1024;
    }
    #{ elastinix.rootAuthorizedKeys = rootAuthorizedKeys; }

    (import ../modules/nixos/bootstrap/base-conf.nix rootAuthorizedKeys)

  ];
}
