{ inputs, ... } :
  { nixpkgs, runSystem, distribution ? "terraform", version ? "1-5-3" } :
let
    tf_pkgs = import inputs."nixpkgs-${distribution}-v${version}" { system = runSystem; config.allowUnfree = true; };
in
  if distribution == "terraform" then
    "${tf_pkgs.terraform}/bin/terraform"
  else
    "${tf_pkgs.opentofu}/bin/tofu"
