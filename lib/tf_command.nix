{ inputs, self, ... } :
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

  pkgs = import nixpkgs { system = runSystem; config.allowUnfree = true; };

  useTfBin = (import ./tf_bin.nix {inherit inputs; }) (terraformBinConf // { inherit nixpkgs runSystem tfBinOverride; });

  bootimgModules = [
    (import ../modules/nixos/bootstrap/base-conf.nix { inherit rootAuthorizedKeys; })
    "${nixpkgs}/nixos/modules/virtualisation/amazon-image.nix"
  ];

  bootstrapImage = (import ./os_config_bootstrap.nix { inherit inputs nixpkgs; }) targetSystem bootimgModules;
  liveConfig = (import ./os_config_live.nix { inherit inputs self nixpkgs; }) targetSystem bootimgModules machineConfig varsfile;

  tf_prelude = ''
    export TF_VAR_ec2_bootstrap_img_path="${bootstrapImage}/nixos_image.vhd";
    export TF_VAR_ec2_host_live_path="${liveConfig}"
  '';

  tf_varfile_arg = if (cmd == "apply" || cmd == "plan" ) then "-var-file=${varsfile}" else "";
in

pkgs.writeShellScriptBin "terraform" '' ${tf_prelude} ${useTfBin} ${cmd} ${tf_varfile_arg} $@''
