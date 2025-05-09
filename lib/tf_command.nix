{nixpkgs,..} : { pkgs, tfBin, cmd ? "", varsfile ? "", bootstrap_img_minimal, ec2conf } :

let
  varfile_arg = if varsfile == "" then "" else "-var-file=${varsfile}";

  prelude = ''
    export TF_VAR_ec2_bootstrap_img_path="${bootstrap_img_minimal}/nixos_image.vhd";
    export TF_VAR_ec2_host_live_path="${ec2conf}"
  '';

in
pkgs.writeShellScriptBin "terraform" ''
  ${prelude}
  ${tfBin} ${cmd} ${varfile_arg} $@
''
