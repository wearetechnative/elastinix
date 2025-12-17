{ inputs }:
  { nixpkgs, targetSystem, machineConfig, varsfile, rootAuthorizedKeys ? [],... } :
let

  tfvars = if varsfile == ""
    then
      {}
    else
      builtins.fromJSON (builtins.readFile varsfile);

  liveConfig = (nixpkgs.lib.nixosSystem {
    system = targetSystem;
    specialArgs = {
      inherit tfvars;
      ec2orAmi = "ec2";
    };
    modules =
      [

        {
          _module.args.nixpkgs = nixpkgs;
          _module.args.targetSystem = targetSystem;
        }

        "${nixpkgs}/nixos/modules/virtualisation/amazon-image.nix"
        (import ../modules/nixos/bootstrap/base-conf.nix rootAuthorizedKeys)

        inputs.agenix.nixosModules.default
        inputs.slack2zammad.nixosModules.slack2zammad
        inputs.jsonify-aws-dotfiles.nixosModules.jsonify-aws-dotfiles
        inputs.nixos-healthchecks.nixosModules.default

        (inputs.import-tree ../modules/nixos/programs)
        (inputs.import-tree ../modules/nixos/services)
        (inputs.import-tree ../modules/nixos/tests)

        {
          environment.systemPackages = [
             inputs.agenix.packages.${targetSystem}.agenix
             inputs.slack2zammad.packages.${targetSystem}.slack2zammad
             inputs.slack2zammad.packages.${targetSystem}.jsonify-aws-dotfiles
          ];
        }

        machineConfig

      ];

  });
in
  liveConfig
