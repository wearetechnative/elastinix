{ nixos-generators }:
{
  tf_command2 = import ./tf_command.nix;

  tf_command = {pkgs, prelude, cmd ? "", varsfile ? "" } :
    let
      varfile_arg = if varsfile == "" then "" else "-var-file=${varsfile}";
    in
    pkgs.writeShellScriptBin "terraform" ''
      ${prelude}
      ${pkgs.terraform}/bin/terraform ${cmd} ${varfile_arg} $@
    '';

  create_bootstrap_img_minimal = { nixpkgs, system, minimalModules } : nixos-generators.nixosGenerate {
    inherit system;
    pkgs = import nixpkgs { inherit system; config.allowUnfree = true; };
    format = "amazon";
    modules = minimalModules ++ [

      "${nixpkgs}/nixos/modules/virtualisation/amazon-image.nix"
      { amazonImage.name = "nixos_image"; amazonImage.sizeMB = 16 * 1024;}
    ];
  };


}
