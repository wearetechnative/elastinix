# Evaluation test for elastinix.services.attic_pull.
#
# Everything here is settled at evaluation time: which nix.settings the module
# renders and which configurations its assertions refuse. That the rendered
# settings actually make a host substitute is tests/attic-pull-vm.nix.
#
# No tfvars in specialArgs on purpose: the module must not need them.
#
# Exposed as checks.<linux-system>.attic-pull in flake.nix.
{ pkgs, lib, agenix, ... }:

let
  base = {
    boot.loader.grub.enable = false;
    fileSystems."/" = { device = "none"; fsType = "tmpfs"; };
    system.stateVersion = lib.trivial.release;
    # Real hosts get this from openssh; agenix asserts on it otherwise.
    age.identityPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
  };

  evalModules = modules:
    (import (pkgs.path + "/nixos/lib/eval-config.nix") {
      system = pkgs.stdenv.hostPlatform.system;
      modules = [ base agenix ] ++ modules;
    }).config;

  evalWith = cfg: evalModules [
    ../modules/nixos/services/service-attic-pull.nix
    cfg
  ];

  # The example from docs/services/attic-pull.md, verbatim.
  documented = { config, ... }: {
    age.secrets.attic-pull = {
      file = ./attic-pull.nix; # stands in for secrets/attic-pull.age
      owner = "root";
      group = "root";
      mode = "400";
    };

    elastinix.services.attic_pull = {
      enable = true;
      endpoint = "https://attic.example.com";
      cache = "infra";
      public_key = "infra:Z/e9fATMRoLBa6kHVJxHJ98PR8fqeVr99TOWnqkAnYc=";
      netrc_file = config.age.secrets.attic-pull.path;
    };
  };

  valid = {
    enable = true;
    endpoint = "https://attic.example.com";
    cache = "infra";
    public_key = "infra:Z/e9fATMRoLBa6kHVJxHJ98PR8fqeVr99TOWnqkAnYc=";
    netrc_file = "/run/agenix/attic-pull";
  };
  secretKey = "infra:82G7rZ9HRmPPmsGwcuGqjgjIjqLaa6GMqVJDRwfSraBn9718BMxGgsFrqQdUnEcn3w9Hx+p5Wv31M5aeqQCdhw==";

  withOpts = extra: evalWith { elastinix.services.attic_pull = valid // extra; };

  failed = c: map (a: a.message) (builtins.filter (a: !a.assertion) c.assertions);
  mentions = needle: c: builtins.any (m: lib.hasInfix needle m) (failed c);
  nixOf = c: {
    substituters = c.nix.settings.substituters or [ ];
    keys = c.nix.settings.trusted-public-keys or [ ];
    netrc = c.nix.settings.netrc-file or null;
  };

  without = evalModules [ ];
  disabled = evalWith { };
  doc = evalWith documented;
  enabled = withOpts { };
  slash = withOpts { endpoint = "https://attic.example.com/"; };

  upstream = "https://cache.nixos.org/";
  upstreamKey = "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY=";
  indexOf = x: xs: lib.lists.findFirstIndex (y: y == x) null xs;

  # Each broken variant must fail naming its own problem; the valid ones pass.
  rejects = [
    { name = "missing endpoint"; opts = { endpoint = null; }; says = "attic_pull.endpoint is not set"; }
    { name = "empty endpoint"; opts = { endpoint = ""; }; says = "attic_pull.endpoint is not set"; }
    { name = "endpoint without scheme"; opts = { endpoint = "attic.example.com"; }; says = "must start with http"; }
    { name = "missing cache"; opts = { cache = null; }; says = "attic_pull.cache is not set"; }
    { name = "cache with slash"; opts = { cache = "infra/x"; }; says = "not a valid Attic cache name"; }
    { name = "cache too long"; opts = { cache = lib.strings.replicate 51 "a"; }; says = "not a valid Attic cache name"; }
    { name = "missing public key"; opts = { public_key = null; }; says = "attic_pull.public_key is not set"; }
    { name = "malformed public key"; opts = { public_key = "infra"; }; says = "<name>:<base64 of 32 bytes>"; }
    { name = "secret key as public key"; opts = { public_key = secretKey; }; says = "is a secret key"; }
    { name = "missing netrc"; opts = { netrc_file = null; }; says = "attic_pull.netrc_file is not set"; }
    { name = "relative netrc"; opts = { netrc_file = "secrets/attic-pull"; }; says = "attic_pull.netrc_file must be an absolute path"; }
  ];

  checks = [
    {
      name = "disabled module changes nothing";
      ok = nixOf disabled == nixOf without && failed disabled == [ ];
      got = builtins.toJSON (nixOf disabled);
    }
    {
      name = "documented example evaluates";
      ok = failed doc == [ ]
        && (nixOf doc).netrc == doc.age.secrets.attic-pull.path
        && lib.elem "https://attic.example.com/infra" (nixOf doc).substituters;
      got = builtins.toJSON { failed = failed doc; nix = nixOf doc; };
    }
    {
      name = "valid configuration passes every assertion";
      ok = failed enabled == [ ];
      got = builtins.toJSON (failed enabled);
    }
    {
      name = "upstream cache kept, attic cache after it";
      ok = let s = (nixOf enabled).substituters; in
        indexOf upstream s != null
        && indexOf "https://attic.example.com/infra" s != null
        && indexOf upstream s < indexOf "https://attic.example.com/infra" s;
      got = builtins.toJSON (nixOf enabled).substituters;
    }
    {
      name = "upstream key kept, cache key after it";
      ok = let k = (nixOf enabled).keys; in
        indexOf upstreamKey k != null
        && indexOf valid.public_key k != null
        && indexOf upstreamKey k < indexOf valid.public_key k;
      got = builtins.toJSON (nixOf enabled).keys;
    }
    {
      name = "netrc-file points at netrc_file";
      ok = (nixOf enabled).netrc == "/run/agenix/attic-pull";
      got = builtins.toJSON (nixOf enabled).netrc;
    }
    {
      name = "trailing slash on the endpoint gives no double slash";
      ok = lib.elem "https://attic.example.com/infra" (nixOf slash).substituters
        && !(builtins.any (lib.hasInfix "//infra") (nixOf slash).substituters);
      got = builtins.toJSON (nixOf slash).substituters;
    }
    {
      name = "no systemd unit added";
      ok = builtins.attrNames enabled.systemd.services == builtins.attrNames disabled.systemd.services;
      got = builtins.toJSON (lib.subtractLists
        (builtins.attrNames disabled.systemd.services)
        (builtins.attrNames enabled.systemd.services));
    }
    {
      name = "http endpoint and +/_/- cache names are accepted";
      ok = failed (withOpts { endpoint = "http://server:8080"; cache = "tn-infra_2+x"; }) == [ ];
      got = builtins.toJSON (failed (withOpts { endpoint = "http://server:8080"; cache = "tn-infra_2+x"; }));
    }
  ] ++ map (r: {
    name = "rejects ${r.name}";
    ok = mentions r.says (withOpts r.opts);
    got = builtins.toJSON (failed (withOpts r.opts));
  }) rejects;

  failures = builtins.filter (c: !c.ok) checks;
in
if failures != [ ]
then throw ''
  attic-pull test failed:
  ${lib.concatMapStringsSep "\n" (c: "  - ${c.name}: got ${c.got}") failures}
''
else pkgs.runCommand "attic-pull-test" { } ''
  echo "${toString (builtins.length checks)} checks passed" > $out
''
