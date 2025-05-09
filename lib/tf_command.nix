{pkgs, tfBin, prelude, cmd ? "", varsfile ? "" } :

let
  varfile_arg = if varsfile == "" then "" else "-var-file=${varsfile}";
in
pkgs.writeShellScriptBin "terraform" ''
  ${prelude}
  ${tfBin} ${cmd} ${varfile_arg} $@
''
