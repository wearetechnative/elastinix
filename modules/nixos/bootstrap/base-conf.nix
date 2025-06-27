{ rootAuthorizedKeys ? [] } :
  { pkgs, config, ... } :

{
  system.stateVersion = "24.05";

  boot.kernel.sysctl = {
    "vm.max_map_count" = "262144";
  };

  boot.extraModulePackages = [
    config.boot.kernelPackages.ena
  ];

  users.users.root.openssh.authorizedKeys.keys = rootAuthorizedKeys;

  services.openssh.enable = true;
  services.amazon-ssm-agent.enable = true;

}
