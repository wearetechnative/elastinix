{inputs, nixpkgs}:
  targetSystem: rootAuthorizedKeys:

(nixpkgs.lib.nixosSystem {
  system = targetSystem;
  modules = [
    "${nixpkgs}/nixos/maintainers/scripts/ec2/amazon-image.nix"
    { nixpkgs.config.allowUnfree = true;
      image.baseName = "nixos_image";
      virtualisation.diskSize = 16 * 1024;
    }
    (import ../modules/nixos/bootstrap/base-conf.nix rootAuthorizedKeys)
  ];
}).config.system.build.amazonImage
