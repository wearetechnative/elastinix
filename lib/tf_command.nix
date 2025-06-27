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

  #ec2conf2 = createEC2Host machineConfig varsfile;

  ec2conf = (import ./os_config_live.nix { inherit inputs nixpkgs; }) targetSystem machineConfig bootimgModules varsfile;

  #  createEC2Host = machineConfig: tfvarsfile:
  #    let
  #
  #      liveConfig = (nixpkgs.lib.nixosSystem {
  #        system = targetSystem;
  #        specialArgs = { inherit tfvarsfile; ec2orAmi = "ec2"; };
  #        modules =
  #          bootimgModules ++
  #          [
  #            {
  #              imports = [
  #
  #                inputs.agenix.nixosModules.default
  #                inputs.nixos-healthchecks.nixosModules.default
  #
  #                (inputs.import-tree ../modules/nixos/programs)
  #                (inputs.import-tree ../modules/nixos/services)
  #                (inputs.import-tree ../modules/nixos/tests)
  #              ];
  #
  #              environment.systemPackages = [
  #                inputs.agenix.packages.${targetSystem}.agenix
  #              ];
  #            }
  #
  #            machineConfig
  #
  #          ];
  #
  #      });
  #
  #    in liveConfig.config.system.build.toplevel;

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
