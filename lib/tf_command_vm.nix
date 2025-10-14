{ inputs, ... } :
  { nixpkgs,
    runSystem,
    machineConfig ? {},
    targetSystem ? "x86_64-linux",
    tfBinOverride ? "",
    terraformBinConf ? { distribution = "terraform"; version = "1-5-3"; },
    cmd ? "apply",
    varsfile ? "" ,
    rootAuthorizedKeys ? [] } :
let

  #pkgsRunSys = import nixpkgs { system = runSystem; };

  #useTfBin = (import ./tf_bin.nix {inherit inputs; }) (terraformBinConf // { inherit nixpkgs runSystem tfBinOverride; });

  #bootstrapImage = (import ./os_config_localvm.nix { inherit inputs nixpkgs; }) targetSystem rootAuthorizedKeys;
  bootstrapImage = (import ./os_config_localvm.nix { inherit inputs; }) { inherit nixpkgs targetSystem rootAuthorizedKeys machineConfig varsfile;};

in

bootstrapImage
