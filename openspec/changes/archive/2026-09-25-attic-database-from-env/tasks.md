## 1. The module

- [x] 1.1 Add `database_url` (null-or-string, default `null`) to
      `service-attic.nix` with a description stating that the per-cache signing
      keypair lives in the database; verify with `nix eval` that the option
      exists and defaults to `null`
- [x] 1.2 Render `services.atticd.settings.database` as `lib.mkForce { }` when
      `database_url` is null and as `{ url = database_url; }` otherwise; verify
      by building `checked-attic-server.toml` for both cases and reading back
      that the null case has no `url` and the explicit case has exactly the
      given URL
- [x] 1.3 Add the assertion refusing a password in `database_url`
      (`user:pass@` and `?password=`); verify both forms fail evaluation with a
      message naming `ATTIC_SERVER_DATABASE_URL`, and a password-less URL passes
- [x] 1.4 Fill in the empty descriptions of `environment_file` and `s3_bucket`,
      naming `ATTIC_SERVER_DATABASE_URL` and `ATTIC_SERVER_TOKEN_RS256_SECRET_BASE64`
      as required variables; verify with `nix eval` on the option descriptions

## 2. Tests

- [x] 2.1 Write `tests/attic-database.nix`: a NixOS VM test importing the real
      module, with local PostgreSQL over TCP and the URL only in the runtime
      environment file; assert migrations ran in PostgreSQL and no `server.db`
      exists
- [x] 2.2 In the same test, create a cache through the attic client, record
      its public key, stop atticd, delete `/var/lib/private/atticd`, start
      again, and assert the cache and key are unchanged
- [x] 2.3 In the same test, start atticd with an environment file lacking
      `ATTIC_SERVER_DATABASE_URL` and assert it fails rather than falling back
      to SQLite
- [x] 2.4 Expose the test as `checks.<system>.attic-database` for the Linux
      systems in `flake.nix`; verify `nix flake show` lists it and
      `nix build .#checks.x86_64-linux.attic-database` passes
- [x] 2.5 Verify `nix flake check --no-build` still evaluates for all
      declared systems

## 3. Docs

- [x] 3.1 Write `docs/services/attic.md`: options, environment file contents,
      agenix example, where cache state lives (keypair in DB, NARs in S3),
      the explicit-SQLite escape hatch and its consequences, and the
      verification recipe; verify every option named exists in the module
- [x] 3.2 Add Attic to `docs/README.md` under Infrastructure Services; verify
      the link resolves
