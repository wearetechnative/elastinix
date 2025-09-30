# Elastinix

**Warning: Api and convensions are subject of change as this is an WIP project.**

Flake with shared build code of the Nixos product family for the AWS cloud.

Use this manage and deploy terraform integrated NixOS AMI's and live EC2 instances.

Compagnion terraform module is here: https://github.com/wearetechnative/terraform-aws-module-elastinix


## Usage

### Example flake

```nix
{
  description = "compute 4 based on elastinix";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";

    elastinix.url = "github:wearetechnative/elastinix/nixos-25.05";

    flake-parts.url = "github:hercules-ci/flake-parts";
    devshell.url = "github:numtide/devshell";
  };

  outputs = inputs@{ flake-parts, nixpkgs, elastinix, ... }:

    flake-parts.lib.mkFlake { inherit inputs; } (top@{ config, withSystem, moduleWithSystem, ... }: {
      systems = [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" "x86_64-darwin" ]; # systems that can run a deployment (in contrast to systems that are a target)
      imports = [
        inputs.devshell.flakeModule
      ];

      perSystem = { config, pkgs, ... }:
        let
          runSystem = pkgs.stdenv.hostPlatform.system;

          varsfile_nonprod = ../../infra_environments/nonprod/nonprod.tfvars.json;
          varsfile_prod = ../../infra_environments/prod/prod.tfvars.json;

          machineArgs = {
            inherit nixpkgs;
            machineConfig = import ./nix/hostconf.nix;
            targetSystem = "x86_64-linux";
            rootAuthorizedKeys = import ./nix/authorized_keys.nix;
          };

        in
          {
          packages = {
            nonProdApply = elastinix.lib.tf_command (machineArgs // { inherit runSystem; varsfile = varsfile_nonprod; });
            prodApply = elastinix.lib.tf_command (machineArgs // { inherit runSystem; varsfile = varsfile_prod; });
          };

        };
    });
}
```

### Addition Terraform commands

```nix

packages = {

    nonProdApply = elastinix.lib.tf_command (machineArgs // { inherit runSystem; varsfile = varsfile_nonprod; });
    prodApply = elastinix.lib.tf_command (machineArgs // { inherit runSystem; varsfile = varsfile_prod; });

    # for demo purposes
    version157 = elastinix.lib.tf_command (
        let
            pkgs-tf157 = import nixpkgs-terraform-1-5-7 { system = runSystem; };
        in {
            inherit nixpkgs runSystem;
            tfBinOverride = "${pkgs-tf157.terraform}/bin/terraform";  # optional alternative terraform binary for current system  (defaults to terraform 1.5.3)
            targetSystem = "x86_64-linux";                            # targetSystem: x86_64-linux | aarch64-linux                (defaults to x86_64-linux)
            cmd = "version";                                          # terraform command                                         (defaults to "apply")
        });

    versionTofu = elastinix.lib.tf_command (
        {
            inherit nixpkgs runSystem;
            terraformBinConf = {
                distribution = "opentofu";
                version = "1-8-7";
            };
            cmd = "version";                                          # terraform command                                         (defaults to "apply")
        });

}
```

## Developer information

### Release RunBook

Publish a new release

- make sure current active nixos version branch is up to date e.g. `nixos-25.05`
- rename `Next Release` in changelog to `nixos-25.05.[newversion]`
- `git tag `nixos-25.05.[newversion]`
- `git push --tags`
- in github create new release based on new tag

## Credits

This project would not have seen the light without the excellent article
[introducing the core design of idea](https://jonascarpay.com/posts/2022-09-19-declarative-deployment.html) by jonas Carpay. 
