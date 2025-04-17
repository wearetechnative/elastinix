{
  description = "Elastix, getting Nix to the Cloud";

  inputs = {
    agenix.url = "github:ryantm/agenix";
  };

  outputs = { self, agenix }: {

    nixosModules.default = import ./modules self;
    lib = import ./lib;
  };
}
