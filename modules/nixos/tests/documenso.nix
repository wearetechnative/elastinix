# NixOS VM test for Documenso module
#
# Run with: nix-build nixos-module-test.nix
# Or: nixos-rebuild build-vm -I nixos-config=./nixos-module-test.nix

{ pkgs ? import <nixpkgs> { } }:

let
  # Test secrets (DO NOT use in production!)
  testSecrets = {
    dbPassword = "test-db-password-123";
    nextAuthSecret = "test-nextauth-secret-0123456789abcdef0123456789abcdef";
    encryptionKey = "test-encryption-key-0123456789abcdef0123456789abcdef";
    encryptionSecondaryKey = "test-encryption-secondary-0123456789abcdef0123456789abcdef";
    certPassphrase = "test-cert-passphrase";
    s3Credentials = ''
      AWS_ACCESS_KEY_ID=test-access-key
      AWS_SECRET_ACCESS_KEY=test-secret-key
    '';
  };

  # Write test secrets to Nix store (only for testing!)
  mkSecretFile = name: content: pkgs.writeText "documenso-test-${name}" content;

in
pkgs.testers.nixosTest {
  name = "documenso-service-test";

  nodes.machine = { config, pkgs, ... }: {
    imports = [ ../services/documenso/default.nix ];

    # PostgreSQL database (bundled for testing)
    services.postgresql = {
      enable = true;
      ensureDatabases = [ "documenso" ];
      ensureUsers = [{
        name = "documenso";
        ensureDBOwnership = true;
      }];
      authentication = ''
        local all all trust
        host all all 127.0.0.1/32 trust
      '';
    };

    # Documenso service
    services.documenso = {
      enable = true;
      publicUrl = "http://localhost:3000";

      database = {
        host = "localhost";
        port = 5432;
        name = "documenso";
        user = "documenso";
        passwordFile = mkSecretFile "db-password" testSecrets.dbPassword;
      };

      smtp = {
        host = "localhost";
        port = 25;
        fromAddress = "test@example.com";
        fromName = "Test Documenso";
      };

      storage = {
        type = "s3";
        bucket = "test-bucket";
        endpoint = "s3.localhost";
        region = "us-east-1";
        credentialsFile = mkSecretFile "s3-credentials" testSecrets.s3Credentials;
      };

      jobs = {
        provider = "bullmq";
      };

      secrets = {
        nextAuthSecretFile = mkSecretFile "nextauth" testSecrets.nextAuthSecret;
        encryptionKeyFile = mkSecretFile "encryption-key" testSecrets.encryptionKey;
        encryptionSecondaryKeyFile = mkSecretFile "encryption-secondary-key" testSecrets.encryptionSecondaryKey;
      };

      signing = {
        autoGenerate = true;
        passphraseFile = mkSecretFile "cert-passphrase" testSecrets.certPassphrase;
      };

      features = {
        disableTelemetry = true;
      };
    };
  };

  testScript = ''
    start_all()

    # Wait for PostgreSQL
    machine.wait_for_unit("postgresql.service")

    # Wait for Redis (BullMQ)
    machine.wait_for_unit("redis-documenso.service")

    # Wait for environment file generation
    machine.wait_for_unit("documenso-env.service")

    # Wait for Documenso service
    machine.wait_for_unit("documenso.service")

    # Wait for HTTP server
    machine.wait_for_open_port(3000)

    # Give it a moment to fully start
    machine.sleep(5)

    # Test 1: Health endpoint
    print("Testing health endpoint...")
    machine.succeed("curl -f http://localhost:3000/api/health")

    # Test 2: Certificate status endpoint
    print("Testing certificate status endpoint...")
    machine.succeed("curl -f http://localhost:3000/api/certificate-status")

    # Test 3: Verify environment file was created
    print("Verifying environment file...")
    machine.succeed("test -f /var/lib/documenso/.env")
    machine.succeed("test $(stat -c '%a' /var/lib/documenso/.env) = '600'")

    # Test 4: Verify certificate was auto-generated
    print("Verifying auto-generated certificate...")
    machine.succeed("test -f /var/lib/documenso/cert.p12")
    machine.succeed("test $(stat -c '%a' /var/lib/documenso/cert.p12) = '400'")

    # Test 5: Verify database migrations ran
    print("Verifying database migrations...")
    machine.succeed(
      "sudo -u postgres psql -d documenso -c '\\dt' | grep -q '_prisma_migrations'"
    )

    # Test 6: Verify Redis is running and has correct config
    print("Verifying Redis configuration...")
    machine.succeed("redis-cli -p 6379 ping | grep -q PONG")
    machine.succeed("redis-cli -p 6379 CONFIG GET appendonly | grep -q yes")

    # Test 7: Verify service can be restarted
    print("Testing service restart...")
    machine.systemctl("restart documenso.service")
    machine.wait_for_unit("documenso.service")
    machine.wait_for_open_port(3000)
    machine.sleep(3)
    machine.succeed("curl -f http://localhost:3000/api/health")

    # Test 8: Verify logs are accessible
    print("Verifying logs...")
    machine.succeed("journalctl -u documenso.service | grep -q 'Starting Documenso'")

    # Test 9: Verify user and group
    print("Verifying user and group...")
    machine.succeed("id documenso")
    machine.succeed("test $(stat -c '%U' /var/lib/documenso) = 'documenso'")

    # Test 10: Verify systemd security hardening
    print("Verifying security hardening...")
    machine.succeed(
      "systemctl show documenso.service | grep -q 'NoNewPrivileges=yes'"
    )
    machine.succeed(
      "systemctl show documenso.service | grep -q 'PrivateTmp=yes'"
    )
    machine.succeed(
      "systemctl show documenso.service | grep -q 'ProtectSystem=strict'"
    )

    print("All tests passed!")
  '';
}
