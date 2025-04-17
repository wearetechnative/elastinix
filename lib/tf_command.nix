{pkgs, prelude, cmd ? "", varsfile ? "" } :

let
  varfile_arg = if varsfile == "" then "" else "-var-file=${varsfile}";
in
pkgs.writeShellScriptBin "terraform" ''
  ${prelude}
  ${pkgs.terraform}/bin/terraform ${cmd} ${varfile_arg} $@
''
