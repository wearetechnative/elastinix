rootAuthorizedKeys:
  { config, lib, ... } :

{
  # options.elastinix.rootAuthorizedKey = lib.mkOption {
  #   description = "The list of authorized keys for root.";
  #   type = lib.types.listOf lib.types.str;
  # };

  system.stateVersion = "24.05";

  boot.kernel.sysctl = {
    "vm.max_map_count" = "262144";

    # The instance first boots the bootstrap image, which has an empty
    # hostName, so apply-ec2-data sets the kernel hostname from EC2 metadata
    # (ip-10-0-2-137.eu-central-1.compute.internal). A switch to the live
    # config only writes /etc/hostname, so the kernel kept the EC2 name and
    # tools like mail(1) sent as root@ip-…compute.internal. systemd-sysctl
    # runs at boot and on every switch that changes this value.
    "kernel.hostname" = lib.mkIf (config.networking.hostName != "") config.networking.hostName;
  };

  boot.extraModulePackages = [
    config.boot.kernelPackages.ena
  ];

  users.users.root.openssh.authorizedKeys.keys = rootAuthorizedKeys;

  services.openssh.enable = true;
  services.amazon-ssm-agent.enable = true;

}
