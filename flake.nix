{
  description = "Elastinix, getting Nix to the Cloud";
  inputs = {

    #nixos 25.11
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11"; # This nixpkgs archive is used by nixos-generators
    nixos-generators.url = "github:nix-community/nixos-generators";
    nixos-generators.inputs.nixpkgs.follows = "nixpkgs";

    #first setup to support multiple terraforms make this a remote module, or just remove
    nixpkgs-terraform-v1-5-3.url = "github:NixOS/nixpkgs/nixos-23.05";
    nixpkgs-terraform-v1-5-7.url = "github:nixos/nixpkgs/3f293ea9ecd5c50e5bd393fd1c560275ea0e6975";
    nixpkgs-opentofu-v1-8-7.url = "github:nixos/nixpkgs/nixos-24.11";

    import-tree.url = "github:vic/import-tree";

    nixos-healthchecks.url = "github:mrvandalo/nixos-healthchecks";

    agenix.url = "github:ryantm/agenix";

    slack2zammad.url = "github:wearetechnative/slack2zammad";
    pontifex = { url = "ssh://git@github.com/TechNative-B-V/pontifex.git"; type = "git"; };
    jsonify-aws-dotfiles.url = "github:wearetechnative/jsonify-aws-dotfiles";
    jirasync.url = "github:wearetechnative/jirasync";
    jirasync.inputs.nixpkgs.follows = "nixpkgs";
    badgersbay.url = "github:wearetechnative/badgersbay";
    #badgersbay.url = "path:/home/wtoorren/data/git/wearetechnative/badgersbay";
    badgersbay.inputs.nixpkgs.follows = "nixpkgs";

    flake-parts.url = "github:hercules-ci/flake-parts";
    devshell.url = "github:numtide/devshell";
    monitoring.url = "github:wearetechnative/monitoring";
  };

  outputs = inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {

      imports = [
        inputs.devshell.flakeModule
        inputs.nixos-healthchecks.flakeModule
      ];

      systems = [ "x86_64-linux" "aarch64-linux" "aarch64-darwin" "x86_64-darwin" ];

      perSystem = _: {
        devshells.default = {};
      };

      flake = {
        #lib.tf_bin = import ./lib/tf_bin.nix { inherit inputs; };
        lib.tf_command = import ./lib/tf_command.nix { inherit inputs; };
        lib.os_config_live = import ./lib/os_config_live.nix { inherit inputs; };

        lib.run_as_vm = import ./lib/cmd_vm.nix { inherit inputs; };

        # HOWTO
        # cp ./result/nixos.qcow2 /tmp/
        # chmod 644 /tmp/nixos.qcow2
        # qemu-kvm -name nixos -m 4G -smp 2 -drive cache=writeback,file=/tmp/nixos.qcow2,id=drive1,if=none,index=1,werror=report \
        #   -device virtio-blk-pci,bootindex=1,drive=drive1 \
        #   -nographic


      };
    };
}
