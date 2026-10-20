# NixOS VM test for elastinix.services.zammad with Elasticsearch 8.
#
# Boots the real module (stub tfvars) against a local PostgreSQL and checks
# what Zammad 7.2 needs from the host: an Elasticsearch it accepts (8.15 up to
# 10, with the bundled ingest-attachment module), the web UI behind nginx, the
# WebSocket endpoints upgraded by nginx, and a search index rebuild that passes
# Zammad's own Elasticsearch version check.
#
# ACME and forceSSL are switched off on the vhost: there is no CA in the VM.
# The flake's pkgs allows the unfree vendored Elasticsearch. Timeouts are
# generous so the test also passes when the builder has no KVM (TCG).
#
# Exposed as checks.<linux-system>.zammad-vm in flake.nix.
{ pkgs, lib, ... }:

let
  # zammad.example.com is Zammad's default fqdn, which ActionCable accepts as
  # request origin on a fresh database.
  domain = "example.com";
  vhost = "zammad.${domain}";
  dbPassword = "zammad-vm-test";
in
pkgs.testers.runNixOSTest {
  name = "zammad-vm";

  node.specialArgs.tfvars = {
    infra_environment = "test";
    environment_domain = domain;
  };

  nodes.machine = { config, ... }: {
    imports = [
      ../modules/nixos/services/service-zammad.nix
      # Hosts enable nginx through this module; the zammad module only adds
      # its virtual host.
      ../modules/nixos/services/service-nginx.nix
    ];

    elastinix.services.nginx.enable = true;

    virtualisation = {
      memorySize = 6144;
      cores = 2;
      # Elasticsearch stops allocating shards above its disk watermarks.
      diskSize = 6144;
    };

    elastinix.services.zammad = {
      enable = true;
      database_username = "zammad";
      database_host = "127.0.0.1";
      database_port = 5432;
      database_name = "zammad";
      secret_key_base_file = "${pkgs.writeText "zammad-secret-key-base"
        "52882ef142066e09ab99ce816ba72522e789505caba224a52d750ec7dc872c2c371b2fd19f16b25dfbdd435a4dd46cb3df9f82eb63fafad715056bdfe25740d6"}";
      password_file = "${pkgs.writeText "zammad-db-password" dbPassword}";
    };

    # Keep the auto-sized heap (half of RAM) from starving Zammad in the VM.
    services.elasticsearch.extraJavaOptions = [
      "-Xms512m"
      "-Xmx512m"
    ];

    # The module expects an external database; provide one locally.
    services.postgresql = {
      enable = true;
      initialScript = pkgs.writeText "zammad-db-init.sql" ''
        CREATE ROLE zammad LOGIN PASSWORD '${dbPassword}';
        CREATE DATABASE zammad OWNER zammad ENCODING 'UTF8';
      '';
    };
    systemd.services.zammad-web = {
      after = [ "postgresql.target" ];
      requires = [ "postgresql.target" ];
      # The first start seeds the database in preStart. Without KVM that takes
      # longer than the upstream 20 minutes; a killed seed is never retried
      # ("Database already has data, skipping seed") and leaves Zammad broken.
      serviceConfig.TimeoutStartSec = lib.mkForce 7200;
    };

    services.nginx.virtualHosts.${vhost} = {
      enableACME = lib.mkForce false;
      forceSSL = lib.mkForce false;
    };

    environment.systemPackages = [
      pkgs.curl
      pkgs.jq
    ];
  };

  testScript = ''
    import json

    def ws_handshake(path):
        # Prints only the status code; the connection stays open after a 101,
        # so --max-time ends it and its exit code is ignored.
        return machine.succeed(
            "curl -s -o /dev/null -w '%{http_code}' --http1.1 --max-time 5"
            " -H 'Host: ${vhost}' -H 'Origin: http://${vhost}'"
            " -H 'Connection: Upgrade' -H 'Upgrade: websocket'"
            " -H 'Sec-WebSocket-Version: 13' -H 'Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ=='"
            f" http://127.0.0.1{path} || true"
        ).strip()

    start_all()

    with subtest("Elasticsearch 8 runs inside Zammad's supported range"):
        machine.wait_for_unit("elasticsearch.service", timeout=1800)
        info = json.loads(machine.succeed("curl -sSf http://127.0.0.1:9200/"))
        version = info["version"]["number"]
        major, minor = (int(x) for x in version.split(".")[:2])
        assert (major, minor) >= (8, 15) and major < 10, f"unsupported Elasticsearch {version}"
        machine.log(f"Elasticsearch {version}")

    with subtest("ingest-attachment is a bundled module, no plugins installed"):
        nodes = json.loads(machine.succeed("curl -sSf http://127.0.0.1:9200/_nodes/plugins"))
        node = next(iter(nodes["nodes"].values()))
        assert node["plugins"] == [], f"unexpected plugins: {node['plugins']}"
        modules = [m["name"] for m in node["modules"]]
        assert "ingest-attachment" in modules, "ingest-attachment module missing"

    with subtest("Elasticsearch listens on loopback only"):
        machine.fail("ss -ltnH | grep ':9200' | grep -v -e '127.0.0.1:9200' -e '\\[::1\\]:9200' -e '\\[::ffff:127.0.0.1\\]:9200'")

    with subtest("Zammad web UI answers through nginx"):
        machine.wait_for_unit("nginx.service")
        machine.wait_for_unit("postgresql.target")
        machine.wait_for_unit("zammad-web.service", timeout=7200)
        machine.wait_for_open_port(3000, timeout=3600)
        machine.wait_until_succeeds(
            "curl -sSfL -H 'Host: ${vhost}' http://127.0.0.1/ | grep '<title>Zammad Helpdesk</title>'",
            timeout=1800,
        )

    with subtest("nginx upgrades the legacy WebSocket on /ws"):
        machine.wait_for_unit("zammad-websocket.service", timeout=1800)
        machine.wait_for_open_port(6042, timeout=1800)
        code = ws_handshake("/ws")
        assert code == "101", f"/ws handshake returned {code}"

    with subtest("nginx upgrades ActionCable on /cable"):
        code = ws_handshake("/cable")
        assert code == "101", f"/cable handshake returned {code}"

    with subtest("search index rebuild passes Zammad's Elasticsearch version check"):
        machine.succeed(
            "zammad run rails r \"Setting.set('es_url', 'http://127.0.0.1:9200')\""
        )
        out = machine.succeed("zammad run rake zammad:searchindex:rebuild 2>&1")
        machine.log(out)
        assert "is not supported" not in out, out
        indices = machine.succeed("curl -sSf 'http://127.0.0.1:9200/_cat/indices?h=index'")
        assert "zammad_production_ticket" in indices, f"no Zammad indices: {indices}"
  '';
}
