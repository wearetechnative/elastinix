{ nixpkgs, elastinixModule, nixos-generators, ... } : { runSystem, targetSystem, tfBin, cmd ? "", varsfile ? "", bootstrap_img_minimal, machineFile, bootstrap-config-module } :

let
  varfile_arg = if varsfile == "" then "" else "-var-file=${varsfile}";

  pkgs = import nixpkgs { system = runSystem; config.allowUnfree = true; };

  ec2conf = createEC2Host machineFile varsfile;

  #bootstrap-config-module = import ../../lib/ec2nix/nix-modules/10-base-conf-2405.nix;

  minimal-modules = [
    bootstrap-config-module
    "${nixpkgs}/nixos/modules/virtualisation/amazon-image.nix"
  ];

  bootstrap_img_minimal = nixos-generators.nixosGenerate {
    system = targetSystem;
    pkgs = import nixpkgs { system = runSystem; config.allowUnfree = true; };
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
            elastinixModule
          ];

      });

    in liveConfig.config.system.build.toplevel;



  prelude = ''
    export TF_VAR_ec2_bootstrap_img_path="${bootstrap_img_minimal}/nixos_image.vhd";
    export TF_VAR_ec2_host_live_path="${ec2conf}"
  '';

in
pkgs.writeShellScriptBin "terraform" ''
  ${prelude}
  ${tfBin} ${cmd} ${varfile_arg} $@
''
