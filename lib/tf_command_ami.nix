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

  bootstrapImage = (import ./os_config_bootstrap_ami.nix { inherit inputs nixpkgs; }) targetSystem rootAuthorizedKeys;
  

  tf_prelude = ''
    export TF_VAR_ec2_bootstrap_img_path="${bootstrapImage}/nixos_image.vhd"

  '';

  tf_varfile_arg = if (cmd == "apply" || cmd == "plan" ) then "-var-file=${varsfile}" else "";
in

pkgsRunSys.writeShellScriptBin "terraform" '' ${tf_prelude} ${useTfBin} ${cmd} ${tf_varfile_arg} $@''

