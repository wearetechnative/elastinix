# Elastinix

**Warning: Api and convensions are subject of change as this is an WIP project.**

Flake with shared build code of the Nixos product family for the AWS cloud.

Use this manage and deploy terraform integrated NixOS AMI's and live EC2 instances.

Compagnion terraform module is here: https://github.com/wearetechnative/terraform-aws-module-elastinix


## Usage inside flake packages:


```nix
packages = {

    nonProdApply = elastinix.lib.tf_command (machineArgs // { varsfile = varsfile_nonprod; });
    prodApply = elastinix.lib.tf_command (machineArgs // { varsfile = varsfile_prod; });

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


## Credits

This project would not have seen the light without the excellent article
[introducing the core design of idea](https://jonascarpay.com/posts/2022-09-19-declarative-deployment.html) by jonas Carpay. 
