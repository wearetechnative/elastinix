# NixOS VM test for the kernel hostname set by base-conf.nix: a host whose
# kernel hostname was set from EC2 metadata gets networking.hostName back on a
# switch, without a reboot.
#
# Exposed as checks.<linux-system>.kernel-hostname-vm in flake.nix.
{ pkgs, lib, ... }:

pkgs.testers.runNixOSTest {
  name = "kernel-hostname-vm";

  nodes.machine = { lib, ... }: {
    imports = [ (import ../modules/nixos/bootstrap/base-conf.nix [ ]) ];

    # Not under test, and not needed in a VM.
    boot.extraModulePackages = lib.mkForce [ ];
    services.amazon-ssm-agent.enable = lib.mkForce false;

    networking.hostName = lib.mkForce "compute9-prod";

    specialisation.renamed.configuration.networking.hostName = lib.mkOverride 40 "compute9-renamed";
  };

  testScript = ''
    machine.wait_for_unit("multi-user.target")

    with subtest("boot sets the kernel hostname from networking.hostName"):
        assert machine.succeed("uname -n").strip() == "compute9-prod"

    # What apply-ec2-data does on the bootstrap image.
    machine.succeed("hostname ip-10-0-2-137.eu-central-1.compute.internal")
    assert machine.succeed("uname -n").strip() == "ip-10-0-2-137.eu-central-1.compute.internal"

    with subtest("a switch that changes the hostname resets the kernel hostname"):
        machine.succeed("/run/current-system/specialisation/renamed/bin/switch-to-configuration test")
        assert machine.succeed("uname -n").strip() == "compute9-renamed"
        assert machine.succeed("hostnamectl --static").strip() == "compute9-renamed"
  '';
}
