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
    }).config;

  gcOf = c: c.services.atticd.settings.garbage-collection;
  logOf = c: c.systemd.services.atticd.environment.RUST_LOG or null;

  defaults = gcOf (evalWith { });
  customInterval = gcOf (evalWith { garbage_collection.interval = "1 hour"; });
  noRetention = gcOf (evalWith { garbage_collection.default_retention_period = null; });

  logDefault = logOf (evalWith { });
  logCustom = logOf (evalWith { log_filter = "attic_server=debug"; });
  logOff = logOf (evalWith { log_filter = null; });

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
    {
      name = "the collector is not silent by default";
      # Without RUST_LOG atticd keeps only `error`, and the collector reports
      # every pass at `info`, so an unset filter means it runs unobserved.
      ok = logDefault == "attic_server=info";
      got = builtins.toJSON logDefault;
    }
    {
      name = "log filter is overridable";
      ok = logCustom == "attic_server=debug";
      got = builtins.toJSON logCustom;
    }
    {
      name = "null log filter sets nothing";
      ok = logOff == null;
      got = builtins.toJSON logOff;
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
