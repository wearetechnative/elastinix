# Make a host a pull consumer of a private Attic cache.
#
# Three Nix settings have to move together, and getting one wrong fails quietly,
# as a deploy that is merely slower than it should be: a netrc without a
# substituter hands credentials to a cache Nix never consults, and a substituter
# without the trusted key makes Nix refuse what it fetches.
{ lib, config, ... }:
let
  cfg = config.elastinix.services.attic_pull;
  opt = "elastinix.services.attic_pull";

  set = v: v != null && v != "";
  matches = re: v: set v && builtins.match re v != null;

  # 32-byte public key vs 64-byte secret key, both `<name>:<base64>`.
  publicKeyRe = "[^:[:space:]]+:[A-Za-z0-9+/]{43}=";
  secretKeyRe = "[^:[:space:]]+:[A-Za-z0-9+/]{86}==";
  # Attic's own rule, attic/src/cache.rs CACHE_NAME_REGEX.
  cacheNameRe = "[A-Za-z0-9][-A-Za-z0-9_+]{0,49}";

  substituter = "${lib.removeSuffix "/" cfg.endpoint}/${cfg.cache}";
in
{
  options.elastinix.services.attic_pull = {

    enable = lib.mkEnableOption "pulling from a private Attic cache";

    endpoint = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "https://attic.example.com";
      description = ''
        Base URL of the Attic server, without the cache name. The substituter
        becomes `<endpoint>/<cache>`.
      '';
    };

    cache = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "infra";
      description = "Name of the Attic cache to pull from.";
    };

    public_key = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "infra:Z/e9fATMRoLBa6kHVJxHJ98PR8fqeVr99TOWnqkAnYc=";
      description = ''
        The cache's public signing key, as `attic cache info` prints it. The host
        accepts every store path this key signs, so push access to the cache is
        what has to be guarded.
      '';
    };

    netrc_file = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "/run/agenix/attic-pull";
      description = ''
        Absolute path to an already decrypted netrc holding the pull token, read
        by the nix daemon as root:

        ```
        machine attic.example.com
        password <JWT>
        ```

        `machine` must be the host of `endpoint`. A string, not a path, so the
        file is never copied into the Nix store; typically an agenix secret with
        owner root and mode 400.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = set cfg.endpoint;
        message = "${opt}.endpoint is not set.";
      }
      {
        assertion = !(set cfg.endpoint) || matches "https?://[^/]+.*" cfg.endpoint;
        message = "${opt}.endpoint must start with http:// or https://, got \"${toString cfg.endpoint}\".";
      }
      {
        assertion = set cfg.cache;
        message = "${opt}.cache is not set.";
      }
      {
        assertion = !(set cfg.cache) || matches cacheNameRe cfg.cache;
        message = ''
          ${opt}.cache "${toString cfg.cache}" is not a valid Attic cache name:
          a letter or digit, then at most 49 of letters, digits, -, _ and +.
        '';
      }
      {
        assertion = set cfg.public_key;
        message = "${opt}.public_key is not set.";
      }
      {
        assertion = !(matches secretKeyRe cfg.public_key);
        message = ''
          ${opt}.public_key is a secret key (64 bytes), not the public key. It
          would be written to the world-readable Nix store; use the public key
          that `attic cache info` prints, and treat this secret as leaked.
        '';
      }
      {
        assertion = !(set cfg.public_key)
          || matches secretKeyRe cfg.public_key
          || matches publicKeyRe cfg.public_key;
        message = "${opt}.public_key must have the form <name>:<base64 of 32 bytes>.";
      }
      {
        assertion = set cfg.netrc_file;
        message = "${opt}.netrc_file is not set.";
      }
      {
        assertion = !(set cfg.netrc_file) || lib.hasPrefix "/" cfg.netrc_file;
        message = "${opt}.netrc_file must be an absolute path, got \"${toString cfg.netrc_file}\".";
      }
    ];

    # mkAfter, never a bare assignment: a bare one drops cache.nixos.org. Attic
    # advertises priority 41 against upstream's 40, so public paths still come
    # from upstream and this cache serves what only we built.
    nix.settings = lib.mkIf (set cfg.endpoint && set cfg.cache && set cfg.public_key && set cfg.netrc_file) {
      substituters = lib.mkAfter [ substituter ];
      trusted-public-keys = lib.mkAfter [ cfg.public_key ];
      netrc-file = cfg.netrc_file;
    };
  };
}
