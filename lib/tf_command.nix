{ inputs, nixpkgs, ... } :
  { runSystem, machineFile, targetSystem ? "x86_64-linux", tfBin ? "", terraformBinConf ? { distribution = "terraform"; version = "1-5-3"; }, cmd ? "apply", varsfile ? "" , rootAuthorizedKeys ? [] } :

let

  pkgsRun = import nixpkgs { system = runSystem; config.allowUnfree = true; };

  #pkgsTf153 = import inputs.nixpkgs-terraform-1-5-3 { system = runSystem; config.allowUnfree = true; };
  #useTfBin = if tfBin == "" then "${pkgsTf153.terraform}/bin/terraform" else tfBin;
  useTfBin = (import ./tf_bin.nix {inherit inputs}) terraformBinConf // { inherit runSystem; });

  tf_varfile_arg = if (cmd == "apply" || cmd == "plan" ) then "-var-file=${varsfile}" else "";

  ec2conf = createEC2Host machineFile varsfile;

  bootstrap-config-module = import ../modules/nixos/bootstrap/base-conf.nix { inherit rootAuthorizedKeys; } ;

  minimal-modules = [
    bootstrap-config-module
    "${nixpkgs}/nixos/modules/virtualisation/amazon-image.nix"
  ];

  bootstrap_img_minimal = inputs.nixos-generators.nixosGenerate {
    system = targetSystem;
    pkgs = import nixpkgs { system = targetSystem; config.allowUnfree = true; };
    format = "amazon";
    modules = minimal-modules ++ [
      { amazonImage.name = "nixos_image"; amazonImage.sizeMB = 16 * 1024;}
    ];
  };

  createEC2Host = machineFile: tfvarsfile:
    let
      defaults = { pkgs, ... }: {
      };

      liveConfig = (nixpkgs.lib.nixosSystem {
        system = targetSystem;
        specialArgs = { inherit tfvarsfile; ec2orAmi = "ec2"; };
        modules =
          minimal-modules ++
          [
            defaults
            (import machineFile)

            {
              imports = [

                inputs.agenix.nixosModules.default
                inputs.nixos-healthchecks.nixosModules.default

                (inputs.import-tree ../modules/nixos/programs)
                (inputs.import-tree ../modules/nixos/services)
                (inputs.import-tree ../modules/nixos/tests)
              ];

              environment.systemPackages = [
                inputs.agenix.packages.${targetSystem}.agenix
              ];
            }
          ];

      });

    in liveConfig.config.system.build.toplevel;

  tf_prelude = ''
    export TF_VAR_ec2_bootstrap_img_path="${bootstrap_img_minimal}/nixos_image.vhd";
    export TF_VAR_ec2_host_live_path="${ec2conf}"
  '';

in
pkgsRun.writeShellScriptBin "terraform" ''
  ${tf_prelude}
  ${useTfBin} ${cmd} ${tf_varfile_arg} $@
''
