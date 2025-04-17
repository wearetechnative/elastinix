{
  description = "Elastix, getting Nix to the Cloud";

  outputs = { self }: {
    nixosModules.default = import ./modules self;
    lib = import ./lib;
  };
}
