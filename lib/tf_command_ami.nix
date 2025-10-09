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

  pkgsRunSys = import nixpkgs { system = runSystem; };

  useTfBin = (import ./tf_bin.nix {inherit inputs; }) (terraformBinConf // { inherit nixpkgs runSystem tfBinOverride; });

  # bootstrapImage = (import ./os_config_bootstrap.nix { inherit inputs nixpkgs; }) targetSystem rootAuthorizedKeys;
  bootstrap_img_full = nixos-generators.nixosGenerate {
    inherit system;
    pkgs = import nixpkgs { inherit system; config.allowUnfree = true; };
    format = "amazon";
    specialArgs = { inherit tfvarsfile; ec2orAmi = "ami"; };
    modules = minimal-modules ++
      [
        defaults
        (import machineFile)
        {
          amazonImage.name = "nixos_image";
          amazonImage.sizeMB = 16 * 1024;
        }
      ];
  };


  tf_prelude = ''
    export TF_VAR_ec2_bootstrap_img_path="${bootstrap_img_full}/nixos_image.vhd";
  '';

  tf_varfile_arg = if (cmd == "apply" || cmd == "plan" ) then "-var-file=${varsfile}" else "";
in
"${bootstrap_img_full}/nixos_image.vhd";

