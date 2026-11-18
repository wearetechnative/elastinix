{ inputs }:
{
  nixpkgs,
  targetSystem,
  machineConfig,
  varsfile,
  rootAuthorizedKeys ? [ ],
  ...
}:
let

  tfvars = if varsfile == "" then { } else builtins.fromJSON (builtins.readFile varsfile);

  liveConfig = nixpkgs.lib.nixosSystem {
    system = targetSystem;
    specialArgs = {
      inherit tfvars;
      ec2orAmi = "ec2";
    };
    modules = [

      {
        _module.args = {
          inherit nixpkgs inputs targetSystem;
        };

      }

      "${nixpkgs}/nixos/modules/virtualisation/amazon-image.nix"
      (import ../modules/nixos/bootstrap/base-conf.nix rootAuthorizedKeys)

      inputs.agenix.nixosModules.default
      inputs.slack2zammad.nixosModules.slack2zammad
      inputs.nixos-healthchecks.nixosModules.default
      inputs.grafana-prometheus.nixosModules.grafana-prometheus
      inputs.pontifex.nixosModules.pontifex
      inputs.optscale.nixosModules.optscale-appliance

      (inputs.import-tree ../modules/nixos/programs)
      (inputs.import-tree ../modules/nixos/services)
      (inputs.import-tree ../modules/nixos/tests)

      {
        documentation.enable = false; # Kills documentation for packages installed via `environment.systemPackages` in to path
        nixpkgs.flake = {
          setFlakeRegistry = false;
          setNixPath = false;
        };
        # Kills nix shell/run/build nixpkgs#pkg
        # Kills nix-shell -p pkg, nix-build '<nixpkgs>'
      }

      machineConfig

    ];

  };
in
liveConfig
