{ inputs, ... } :
  { nixpkgs, runSystem, machineConfig ? {}, targetSystem ? "x86_64-linux", tfBin ? "", terraformBinConf ? { distribution = "terraform"; version = "1-5-3"; }, cmd ? "apply", varsfile ? "" , rootAuthorizedKeys ? [] } :
let

  pkgsRun = import nixpkgs { system = runSystem; config.allowUnfree = true; };

  useTfBin = if tfBin == ""
    then (import ./tf_bin.nix {inherit inputs;}) (terraformBinConf // { inherit nixpkgs runSystem; })
    else tfBin;

  bootimgModules = [
    (import ../modules/nixos/bootstrap/base-conf.nix { inherit rootAuthorizedKeys; })
    "${nixpkgs}/nixos/modules/virtualisation/amazon-image.nix"
  ];

  bootstrapImage = inputs.nixos-generators.nixosGenerate {
    system = targetSystem;
    pkgs = import nixpkgs { system = targetSystem; config.allowUnfree = true; };
    format = "amazon";
    modules = bootimgModules ++ [
      { amazonImage.name = "nixos_image"; amazonImage.sizeMB = 16 * 1024;}
    ];
  };

  ec2conf = (import ./os_config_live.nix { inherit inputs nixpkgs; }) targetSystem machineConfig bootimgModules varsfile;

  tf_prelude = ''
    export TF_VAR_ec2_bootstrap_img_path="${bootstrapImage}/nixos_image.vhd";
    export TF_VAR_ec2_host_live_path="${ec2conf}"
  '';

  tf_varfile_arg = if (cmd == "apply" || cmd == "plan" ) then "-var-file=${varsfile}" else "";
in
pkgsRun.writeShellScriptBin "terraform" ''
  ${tf_prelude}
  ${useTfBin} ${cmd} ${tf_varfile_arg} $@
''
