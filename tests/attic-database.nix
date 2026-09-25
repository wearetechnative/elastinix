# NixOS VM test for elastinix.services.attic: the database URL comes only from
# the environment file, and cache identity lives in that database.
#
# Lives outside modules/nixos/ because import-tree imports every .nix file there
# as a NixOS module. Exposed as checks.<linux-system>.attic-database in flake.nix.
{ pkgs, lib, ... }:

let
  dbUrl = "postgresql://attic:attic-test-password@127.0.0.1:5432/attic";

  # Throwaway token signing key for the test only.
  tokenSecret = pkgs.runCommand "attic-test-token-secret" { } ''
    ${lib.getExe pkgs.openssl} genrsa -traditional 4096 | ${pkgs.coreutils}/bin/base64 -w0 > $out
  '';
in
pkgs.testers.runNixOSTest {
  name = "attic-database";

  node.specialArgs.tfvars = {
    environment_domain = "example.test";
    infra_environment = "test";
  };

  nodes.machine = {
    imports = [ ../modules/nixos/services/service-attic.nix ];

    elastinix.services.attic = {
      enable = true;
      environment_file = "/run/attic.env";
      s3_bucket = "attic-test";
    };

    # The environment file is written by the test script; do not start at boot.
    systemd.services.atticd.wantedBy = lib.mkForce [ ];

    # The nginx/ACME front is not under test and has no network here.
    services.nginx.enable = lib.mkForce false;
    security.acme = {
      acceptTerms = true;
      defaults.email = "ops@example.test";
    };

    services.postgresql = {
      enable = true;
      enableTCPIP = true;
      ensureDatabases = [ "attic" ];
      ensureUsers = [
        {
          name = "attic";
          ensureDBOwnership = true;
        }
      ];
      authentication = ''
        host attic attic 127.0.0.1/32 scram-sha-256
      '';
    };

    environment.systemPackages = [ pkgs.attic-client ];
    virtualisation.memorySize = 2048;
  };

  testScript = ''
    token_secret = open("${tokenSecret}").read().strip()

    def write_env(with_db):
        lines = [f"ATTIC_SERVER_TOKEN_RS256_SECRET_BASE64={token_secret}"]
        if with_db:
            lines.append("ATTIC_SERVER_DATABASE_URL=${dbUrl}")
        machine.succeed("install -m 0600 /dev/null /run/attic.env")
        machine.succeed("cat > /run/attic.env <<'EOF'\n" + "\n".join(lines) + "\nEOF")

    def cache_public_key(name):
        out = machine.succeed(f"attic cache info {name} 2>&1")
        keys = [l.split(":", 1)[1].strip() for l in out.splitlines() if "Public Key" in l]
        assert len(keys) == 1, f"no public key in: {out}"
        return keys[0]

    machine.wait_for_unit("multi-user.target")
    machine.wait_for_unit("postgresql.target")
    machine.succeed("sudo -u postgres psql -c \"ALTER USER attic PASSWORD 'attic-test-password'\"")

    with subtest("generated config carries no database url"):
        toml = machine.succeed(
            "systemctl show atticd -p ExecStart --value | grep -o '/nix/store/[^ ]*-checked-attic-server.toml' | head -1"
        ).strip()
        content = machine.succeed(f"cat {toml}")
        print(content)
        assert "sqlite" not in content, content
        assert "url" not in machine.succeed(f"sed -n '/^\\[database\\]/,/^\\[/p' {toml}")

    with subtest("missing ATTIC_SERVER_DATABASE_URL fails instead of falling back to SQLite"):
        write_env(with_db=False)
        machine.execute("systemctl start atticd.service")
        machine.wait_until_succeeds("[ $(systemctl show atticd -p NRestarts --value) -ge 1 ]", timeout=60)
        machine.fail("curl -sf http://127.0.0.1:8080/")
        machine.fail("test -e /var/lib/private/atticd/server.db")
        machine.succeed("journalctl -u atticd.service | grep -q 'Database URL must be specified'")
        machine.succeed("systemctl stop atticd.service")
        machine.execute("systemctl reset-failed atticd.service")

    with subtest("atticd runs on PostgreSQL from the environment file"):
        write_env(with_db=True)
        machine.succeed("systemctl start atticd.service")
        machine.wait_for_unit("atticd.service")
        machine.wait_for_open_port(8080)
        tables = machine.succeed("sudo -u postgres psql -d attic -tAc \"select count(*) from information_schema.tables where table_name = 'cache'\"").strip()
        assert tables == "1", f"attic schema not in PostgreSQL: {tables}"
        machine.fail("test -e /var/lib/private/atticd/server.db")

    with subtest("cache and its key survive loss of the local state directory"):
        token = machine.succeed(
            "atticd-atticadm make-token --sub test --validity 1d --create-cache '*' --pull '*' --push '*' --configure-cache '*'"
        ).strip()
        machine.succeed(f"attic login local http://127.0.0.1:8080 {token}")
        machine.succeed("attic cache create tn-test")
        key_before = cache_public_key("tn-test")
        stored = machine.succeed("sudo -u postgres psql -d attic -tAc \"select count(*) from cache where name = 'tn-test'\"").strip()
        assert stored == "1", stored

        machine.succeed("systemctl stop atticd.service")
        machine.succeed("rm -rf /var/lib/private/atticd /var/lib/atticd")
        machine.succeed("systemctl start atticd.service")
        machine.wait_for_open_port(8080)

        key_after = cache_public_key("tn-test")
        assert key_before == key_after, f"{key_before} != {key_after}"
        machine.fail("test -e /var/lib/private/atticd/server.db")
  '';
}
