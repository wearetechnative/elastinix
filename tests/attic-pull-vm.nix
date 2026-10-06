# NixOS VM test for elastinix.services.attic_pull: a host with the module
# enabled substitutes a store path from a private Attic cache, and only once its
# netrc holds a pull token.
#
# The server is upstream services.atticd with local storage and SQLite, not
# elastinix.services.attic: the server module is not under test, and its S3
# backend has no endpoint inside a VM.
#
# Exposed as checks.<linux-system>.attic-pull-vm in flake.nix.
{ pkgs, lib, ... }:

let
  # Throwaway keypair for this test only. The client's nix.conf is fixed at
  # build time, so the cache is created with this keypair through the API
  # instead of the random one `attic cache create` would generate.
  cacheSecretKey = "attic-pull-test-1:82G7rZ9HRmPPmsGwcuGqjgjIjqLaa6GMqVJDRwfSraBn9718BMxGgsFrqQdUnEcn3w9Hx+p5Wv31M5aeqQCdhw==";
  cachePublicKey = "attic-pull-test-1:Z/e9fATMRoLBa6kHVJxHJ98PR8fqeVr99TOWnqkAnYc=";

  serverEnv = pkgs.runCommand "attic-pull-test-server-env" { } ''
    printf 'ATTIC_SERVER_TOKEN_RS256_SECRET_BASE64=%s\n' \
      "$(${lib.getExe pkgs.openssl} genrsa -traditional 4096 | ${pkgs.coreutils}/bin/base64 -w0)" > $out
  '';

  createCache = pkgs.writeText "attic-pull-test-create-cache.json" (builtins.toJSON {
    keypair.Keypair = cacheSecretKey;
    is_public = false;
    store_dir = "/nix/store";
    priority = 41;
    upstream_cache_key_names = [ "cache.nixos.org-1" ];
  });
in
pkgs.testers.runNixOSTest {
  name = "attic-pull";

  nodes.server = {
    services.atticd = {
      enable = true;
      environmentFile = "${serverEnv}";
      settings = {
        listen = "[::]:8080";
        api-endpoint = "http://server:8080/";
        storage = {
          type = "local";
          path = "/var/lib/atticd/storage";
        };
        chunking = {
          nar-size-threshold = 64 * 1024;
          min-size = 16 * 1024;
          avg-size = 64 * 1024;
          max-size = 256 * 1024;
        };
      };
    };
    networking.firewall.allowedTCPPorts = [ 8080 ];
    environment.systemPackages = [ pkgs.attic-client pkgs.curl ];
    virtualisation.memorySize = 2048;
  };

  nodes.client = {
    imports = [ ../modules/nixos/services/service-attic-pull.nix ];

    elastinix.services.attic_pull = {
      enable = true;
      endpoint = "http://server:8080/";
      cache = "infra";
      public_key = cachePublicKey;
      netrc_file = "/run/attic-pull-netrc";
    };
  };

  testScript = ''
    start_all()
    server.wait_for_unit("atticd.service")
    server.wait_for_open_port(8080)

    with subtest("private cache with a known keypair holds a path the client lacks"):
        admin = server.succeed(
            "atticd-atticadm make-token --sub admin --validity 1d"
            " --create-cache '*' --configure-cache '*' --push '*' --pull '*'"
        ).strip()
        server.succeed(
            "curl -sf -X POST http://127.0.0.1:8080/_api/v1/cache-config/infra"
            f" -H 'Authorization: Bearer {admin}' -H 'Content-Type: application/json'"
            " -d @${createCache}"
        )
        server.succeed(f"attic login local http://127.0.0.1:8080 {admin}")
        info = server.succeed("attic cache info local:infra 2>&1")
        assert "${cachePublicKey}" in info, info
        assert "Public: false" in info, info

        path = server.succeed(
            "echo \"attic-pull $(cat /proc/sys/kernel/random/uuid)\" > /tmp/payload"
            " && nix-store --add /tmp/payload"
        ).strip()
        server.succeed(f"attic push local:infra {path}")
        client.fail(f"nix-store --check-validity {path}")

    with subtest("nix.conf carries upstream first, then the attic cache"):
        conf = client.succeed("cat /etc/nix/nix.conf")
        subs = next(l for l in conf.splitlines() if l.startswith("substituters ="))
        assert subs.index("https://cache.nixos.org/") < subs.index("http://server:8080/infra"), subs
        assert "netrc-file = /run/attic-pull-netrc" in conf, conf

    with subtest("without the netrc the private cache yields nothing"):
        client.fail(f"nix-store --realise {path}")
        client.fail(f"nix-store --check-validity {path}")

    with subtest("with the netrc the path is substituted from the cache"):
        pull = server.succeed(
            "atticd-atticadm make-token --sub client --validity 1d --pull infra"
        ).strip()
        client.succeed("install -m 0400 /dev/null /run/attic-pull-netrc")
        client.succeed(f"printf 'machine server\\npassword %s\\n' '{pull}' > /run/attic-pull-netrc")
        # The failed attempt above left negative lookups in the narinfo cache.
        client.succeed("rm -rf /root/.cache/nix")
        client.succeed(f"nix-store --realise {path}")
        client.succeed(f"nix-store --check-validity {path}")
        assert client.succeed(f"cat {path}") == server.succeed(f"cat {path}")
  '';
}
