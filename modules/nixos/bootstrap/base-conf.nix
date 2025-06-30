{ config, lib, ... } :

{
  options.elastinix.rootAuthorizedKey = lib.mkOption {
    description = "The list of authorized keys for root.";
    type = lib.types.listOf lib.types.str;
  };

  system.stateVersion = "24.05";

  boot.kernel.sysctl = {
    "vm.max_map_count" = "262144";
  };

  boot.extraModulePackages = [
    config.boot.kernelPackages.ena
  ];

  users.users.root.openssh.authorizedKeys.keys = config.elastinix.rootAuthorizedKeys;

  services.openssh.enable = true;
  services.amazon-ssm-agent.enable = true;

}
