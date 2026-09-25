# Evaluation test for elastinix.services.attic.garbage_collection.
#
# Deliberately not a VM test: every scenario is about what the module renders
# into the attic server configuration, which is settled at evaluation time.
# Booting a machine to read one attrset would cost minutes and prove no more.
#
# Exposed as checks.<linux-system>.attic-garbage-collection in flake.nix.
{ pkgs, lib, ... }:

let
  evalWith = extra:
    (import (pkgs.path + "/nixos/lib/eval-config.nix") {
      system = pkgs.stdenv.hostPlatform.system;
      specialArgs.tfvars = {
        environment_domain = "example.test";
        infra_environment = "test";
      };
      modules = [
        ../modules/nixos/services/service-attic.nix
        {
          elastinix.services.attic = {
            enable = true;
            environment_file = "/run/attic.env";
            s3_bucket = "attic-test";
          } // extra;
          # Not under test, and it drags in ACME.
          services.nginx.enable = lib.mkForce false;
          boot.loader.grub.enable = false;
          fileSystems."/" = { device = "none"; fsType = "tmpfs"; };
          system.stateVersion = lib.trivial.release;
        }
      ];
    }).config.services.atticd.settings.garbage-collection;

  defaults = evalWith { };
  customInterval = evalWith { garbage_collection.interval = "1 hour"; };
  noRetention = evalWith { garbage_collection.default_retention_period = null; };

  checks = [
    {
      name = "defaults render both keys";
      ok = defaults.interval == "12 hours"
        && defaults.default-retention-period == "90 days";
      got = builtins.toJSON defaults;
    }
    {
      name = "interval is overridable";
      ok = customInterval.interval == "1 hour"
        && customInterval.default-retention-period == "90 days";
      got = builtins.toJSON customInterval;
    }
    {
      name = "null retention renders zero, key still present";
      ok = noRetention.default-retention-period == "0"
        && noRetention.interval == "12 hours";
      got = builtins.toJSON noRetention;
    }
  ];

  failures = builtins.filter (c: !c.ok) checks;
in
if failures != [ ]
then throw ''
  attic garbage-collection test failed:
  ${lib.concatMapStringsSep "\n" (c: "  - ${c.name}: got ${c.got}") failures}
''
else pkgs.runCommand "attic-garbage-collection-test" { } ''
  echo "${toString (builtins.length checks)} checks passed" > $out
''
