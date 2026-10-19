# Zammad

Runs the Zammad helpdesk (`services.zammad` from nixpkgs). It is wired to an
external PostgreSQL database, a local Redis, a local Elasticsearch 8 and an
nginx virtual host `zammad.<environment_domain>` with ACME TLS.

Elastinix builds both Zammad (from `github.com/zammad/zammad` at a pinned
revision) and Elasticsearch 8 (from Elastic's release tarball) itself, so
neither version depends on the nixpkgs pin. nixpkgs only ships Elasticsearch
7.17, and Zammad 7.2 refuses anything below 8.15.

## Options

All options live under `elastinix.services.zammad`.

| Option                  | Type    | Default                       | Description                               |
| ----------------------- | ------- | ----------------------------- | ----------------------------------------- |
| `enable`                | bool    | `false`                       | Enable Zammad                             |
| `package`               | package | elastinix build (see below)   | Zammad package to run                     |
| `database_username`     | str     | —                             | PostgreSQL user                           |
| `database_host`         | str     | —                             | PostgreSQL host                           |
| `database_port`         | int     | —                             | PostgreSQL port                           |
| `database_name`         | str     | —                             | PostgreSQL database                       |
| `secret_key_base_file`  | str     | —                             | Path to the Rails `secret_key_base` file  |
| `password_file`         | str     | —                             | Path to the database password file        |

`secret_key_base_file` and `password_file` are path strings, so the secrets
never enter the Nix store. Point them at agenix secrets
(`config.age.secrets.<name>.path`).

### `package`

The default is `pkgs.callPackage <elastinix>/pkgs/zammad/package.nix { }`. It
is built per service, not through an overlay, so `pkgs.zammad` stays the
nixpkgs package for every other module. To run the nixpkgs build instead:

```nix
elastinix.services.zammad.package = pkgs.zammad;
```

The [Zammad Security Advisory monitor](zammad-advisory-monitor.md) reads
`package.version`, so it follows whatever package is configured here.

## Elasticsearch

The module runs the upstream `services.elasticsearch` with the elastinix build
of Elasticsearch **8.19.23** (`pkgs/elasticsearch/`, flake output
`.#elasticsearch`). It is set inside this module only; `pkgs.elasticsearch`
stays 7.17 for everything else.

The node is local-only:

```yaml
network.host: 127.0.0.1
discovery.type: single-node
xpack.security.enabled: false
xpack.ml.enabled: false
http.max_content_length: 400mb
```

- No plugins. `ingest-attachment`, which Zammad uses to index attachment
  content, has been a bundled module since Elasticsearch 8.4.
- `services.elasticsearch.single_node` is `false` on purpose. The upstream
  module adds `gateway.auto_import_dangling_indices` in single-node mode,
  and Elasticsearch 8 refuses to start with that setting. Single-node
  discovery is set in `extraConf` instead.
- Java is nixpkgs' JDK 25. The bundled JDK is not installed. Don't go back
  to JDK 21: Elasticsearch then picks the `COMPAT` locale provider, and its
  entitlement checks refuse to load its own calendar provider at startup.
- The license is `elastic20` (unfree), the same as the nixpkgs 7.17 package.
  A host that already allowed `elasticsearch` keeps working unchanged.
- Elasticsearch sizes its heap to half of RAM by default. To cap it on small
  hosts:

  ```nix
  services.elasticsearch.extraJavaOptions = [ "-Xms1g" "-Xmx1g" ];
  ```

Zammad's `es_url` setting (`http://127.0.0.1:9200`) is a database setting
owned by Zammad, not by this module.

To bump Elasticsearch, change `version` and both sha512 hashes in
`pkgs/elasticsearch/package.nix`. Take the hashes from
`https://artifacts.elastic.co/downloads/elasticsearch/elasticsearch-<version>-linux-<arch>.tar.gz.sha512`.
Stay on 8.x until every host's indices were created by 8.x (a search index
rebuild does that): Elasticsearch 9 cannot open indices created by 7.x.

## nginx

The virtual host `zammad.<environment_domain>` (ACME, HTTPS forced) has:

| Location | Upstream                                    | WebSocket |
| -------- | ------------------------------------------- | --------- |
| `/`      | `127.0.0.1:<services.zammad.port>`          | no        |
| `/cable` | `127.0.0.1:<services.zammad.port>`          | yes       |
| `/ws`    | `127.0.0.1:<services.zammad.websocketPort>` | yes       |

All locations use `recommendedProxySettings`. Zammad 7.2 takes the request
scheme only from `X-Forwarded-Proto`, and authenticates the legacy WebSocket
(`/ws`) from the session cookie when the `Origin` matches
`<http_type>://<fqdn>`.

## Where the version is pinned

`pkgs/zammad/source.json` is the single source of truth:

```json
{
  "owner": "zammad",
  "repo": "zammad",
  "rev": "295796a2df0b38a579846c017383835657687a22",
  "hash": "sha256-PDrBkRi/hT7IM3Ed1WZ5seoE6EKQVIJp65wLz3bWQew=",
  "fetchSubmodules": true,
  "version": "7.2.2"
}
```

The rest of `pkgs/zammad/` is a copy of the nixpkgs recipe
(`pkgs/by-name/za/zammad`):

- `package.nix`: the build. Ruby gems via `bundlerEnv`, frontend via pnpm, `rake assets:precompile`.
- `gemset.nix`: Ruby gems, generated by bundix from the tag's `Gemfile.lock`.
- `fix-sendmail-location.diff`: points Zammad at `/run/wrappers/bin/sendmail`.
- `update.sh` and `update.nix`: the update script and its wrapper.

The pnpm dependency hash (`pnpmDeps.hash`) lives in `package.nix`.

The flake exposes the build as `packages.<system>.zammad` for `x86_64-linux`
and `aarch64-linux`:

```bash
nix build .#zammad
```

## Updating Zammad

Bumps are manual. The advisory monitor tells you when one is needed. Check
upstream's `BREAKING_CHANGES.md` for the target version first. Zammad runs
database migrations on start and does not support downgrades.

1. **Regenerate `source.json` and `gemset.nix`** for the tag, from the repository root:

   ```bash
   nix run .#zammad.updateScript -- <tag> ./pkgs/zammad
   ```

   This prefetches the tag, writes `source.json` (with `version`) and runs
   bundix on the tag's `Gemfile.lock`. It only writes the files once both have
   been generated. Without a tag it prints usage and exits non-zero.

2. **Refresh the pnpm hash.** In `pkgs/zammad/package.nix`, set
   `pnpmDeps.hash = lib.fakeHash;`, then:

   ```bash
   nix build .#zammad
   ```

   The build fails with a hash mismatch. Copy the `got:` hash into `pnpmDeps.hash`.

   Also check `packageManager` and `engines` in the tag's `package.json`. If
   it needs a newer pnpm major, switch `pnpm_11` in `package.nix` (the
   argument, the `nativeBuildInputs` entry and `fetchPnpmDeps { pnpm = ...; }`).
   Zammad 7.2 needs pnpm ≥ 11 and Node ≥ 24.

   bundix writes `gemset.nix` unformatted. Run `nixfmt pkgs/zammad/gemset.nix`
   to keep the diff readable.

3. **Build** the package and check the version:

   ```bash
   nix build .#zammad
   nix eval --raw .#zammad.version
   ```

4. **Run the VM test**. It boots the module with Elasticsearch 8 and
   rebuilds the search index:

   ```bash
   nix build .#checks.x86_64-linux.zammad-vm -L
   ```

5. **Push to attic** so hosts don't compile Zammad themselves. The flake
   output and the host's `services.zammad.package` are the same derivation
   for the same nixpkgs:

   ```bash
   attic push technative:tn-infra $(nix build .#zammad .#elasticsearch --no-link --print-out-paths)
   ```

6. **Commit** `pkgs/zammad/` and roll out by re-pinning elastinix in the
   consuming repositories. Take a database dump before deploying a new minor
   or major version.

## Notes

- The first build after a bump takes a while (gem env + asset precompile).
  cache.nixos.org does not have it.
- The recipe stays close to nixpkgs on purpose: compare `pkgs/zammad/` with
  `pkgs/by-name/za/zammad` in nixpkgs to port upstream fixes.

## Upgrading a host from Zammad 7.1 / Elasticsearch 7

Neither Zammad (database migrations) nor Elasticsearch (index metadata) can
be downgraded once the new version has started. Per host:

1. Make sure `.#zammad` and `.#elasticsearch` are in attic (see above).
2. Dump the Zammad database (`elastinix.services.psqldump`, or `pg_dump` by
   hand).
3. Stop Elasticsearch and move its data aside:

   ```bash
   systemctl stop elasticsearch
   mv /var/lib/elasticsearch /var/lib/elasticsearch-7.17
   ```

   A fresh data directory is the simplest path, because the index is rebuilt
   from the database anyway. Elasticsearch 8 can also open the 7.17 data in
   place.
4. Re-pin elastinix and deploy. Zammad runs its migrations when
   `zammad-web` starts.
5. Rebuild the search index (Zammad 7.2 adds the `publication_state` field):

   ```bash
   zammad run rake zammad:searchindex:rebuild
   ```

6. Check the Zammad settings `http_type` (`https`) and `fqdn`
   (`zammad.<environment_domain>`). Since 7.2 the legacy WebSocket only
   authenticates when the browser's `Origin` matches them.
7. Check the health check (`/api/v1/monitoring/health_check`). Since 7.2 it
   reports import mode and `system_init_done = false` as issues.

Rollback: restore the database dump and `/var/lib/elasticsearch-7.17`, and
re-pin elastinix to before the upgrade.
