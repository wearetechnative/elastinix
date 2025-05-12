{ nixpkgs, elastinixModule, nixos-generators, nixpkgs-terraform-1-5-3 } :
  { runSystem, machineFile, targetSystem ? "x86_64-linux", tfBin ? "", cmd ? "apply", varsfile, rootAuthorizedKeys ? [] } :

let
  varfile_arg = if (cmd == "apply" || cmd == "plan" ) then "-var-file=${varsfile}" else "";

  pkgs = import nixpkgs { system = runSystem; config.allowUnfree = true; };

  pkgsTf153 = import nixpkgs-terraform-1-5-3 { system = runSystem; config.allowUnfree = true; };

  useTfBin = if tfBin == "" then "${pkgsTf153.terraform}/bin/terraform" else tfBin;

  ec2conf = createEC2Host machineFile varsfile;

  bootstrap-config-module = import ../modules/bootstrap/base-conf.nix { inherit rootAuthorizedKeys; } ;

  minimal-modules = [
    bootstrap-config-module
    "${nixpkgs}/nixos/modules/virtualisation/amazon-image.nix"
  ];

  bootstrap_img_minimal = nixos-generators.nixosGenerate {
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
  ${useTfBin} ${cmd} ${varfile_arg} $@
''
