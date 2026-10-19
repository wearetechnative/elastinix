# Design

## Context

See proposal.md (Why). Facts that shape the approach:

- **Upstream NixOS module (`services.elasticsearch`)**:
  - It sets `ES_HOME = dataDir` and `ES_PATH_CONF = dataDir/config`.
  - In `preStart` it symlinks the package's `lib/`, `modules/` and a plugins env into `dataDir`, and copies `config/jvm.options` from the package.
  - For package versions ≥ 7 with `single_node = true` it adds `gateway.auto_import_dangling_indices: true`. Elasticsearch 8 removed that setting and refuses to start with it.
- **Elasticsearch 8 tarball (8.19.23)**:
  - `bin/elasticsearch` → `elasticsearch-cli` → `elasticsearch-env`. The env script derives `ES_HOME` from the script path, which would make it the read-only store path, so data and logs would default into it.
  - Java is taken from `ES_JAVA_HOME` or the bundled `jdk/`. `JAVA_HOME` is ignored.
  - Native code ships in `lib/platform/linux-*/` (libvec, libzstd) and `modules/x-pack-ml/platform/linux-*/` (ML controller plus its bundled libraries).
  - `ingest-attachment` is a bundled module.
- **nixpkgs 7.x derivation**: it already solves the same problems for 7.17 with an `es-home` patch, `JAVA_HOME` set to `jre_headless`, and `autoPatchelfHook`.
- **Zammad 7.2.2**: Ruby 3.4.9 (unchanged), `pnpm-lock.yaml` v9 (unchanged), `packageManager: pnpm@11.25.0`, engines `node >=24, pnpm >=11`. nixos-26.05 has `pnpm_11` 11.11.0 and nodejs 24.16. The nixpkgs pnpm hook sets `manage-package-manager-versions false` for pnpm 11, so the `packageManager` pin does not trigger a download.
- **Our nginx vhost** proxies only `/`, without proxy headers. The upstream module's own (unused) `nginx.configure` vhost shows what Zammad needs: `/cable` and `/ws` with WebSocket upgrades, and recommended proxy settings.

## Goals / Non-Goals

**Goals:**

- Zammad 7.2.2 with an Elasticsearch it accepts, on the existing upstream modules, with no fork of `services.elasticsearch` or `services.zammad`.
- An automated VM test that proves Zammad accepts the backend, not only that the code evaluates.

**Non-Goals:**

- Elasticsearch 9.x. Zammad supports it, but 9 cannot open indices created by 7.x, so an in-place upgrade on compute3 would be impossible. 8.19 can, and it is still maintained.
- Configuring Zammad's `es_url`, `http_type` or `fqdn` from Nix. These are database settings that Zammad owns. The runbook covers them.
- Exposing Elasticsearch beyond loopback, or securing it with xpack.
- Changing the Zammad recipe beyond the version bump and the pnpm major.

## Decisions

### D1: Repackage the upstream tarball natively, not an OCI container

`pkgs/elasticsearch/package.nix` mirrors the nixpkgs 7.x derivation, adapted to the 8.x layout.

- *Why*: hosts keep one systemd service from the upstream module, and the store paths are visible to vulnix and the existing scanning. It is consistent with vendoring Zammad, and it is pushed to attic like any other package.
- *Alternative*: `virtualisation.oci-containers` with `docker.elastic.co/elasticsearch/elasticsearch:8.19.x`. That is simpler to start, but it adds a container runtime to Zammad hosts, a second update path and image scanning. Rejected.

### D2: `ES_HOME` from the environment, Java from nixpkgs

- An `es-home.patch` on `bin/elasticsearch-env` keeps a pre-set `ES_HOME` and only derives it from the script path when it is unset. This is softer than the 7.x patch, which aborts, so the CLI tools still work outside the service.
- `postPatch` substitutes a default `ES_JAVA_HOME=${jdk25_headless.home}` into `elasticsearch-env`, so every CLI tool (server, keystore, plugin, node) runs on the same JDK without per-tool wrappers. A user-set `ES_JAVA_HOME` still wins.
- The bundled `jdk/` is not installed (335 MB less, and nothing to patchelf). JDK 25 is the newest LTS in nixpkgs (Elastic bundles JDK 27 with 8.19.23). JDK 21 was tried first and fails: ES selects `-Djava.locale.providers=SPI,COMPAT` below JDK 23. That path instantiates `IsoCalendarDataProvider` lazily, and the entitlement checks refuse it (`NotEntitledException`, "fatal exception while booting"), unless log4j's stock rolling-file config happened to initialise `Calendar` before entitlements were bootstrapped. The upstream module's console-only `logging` default triggers it every time. The VM test surfaced this, and it was reproduced locally. On JDK 25 the providers are `CLDR,…` and the node starts with the console-only logging.
- `installPhase` copies `bin config lib modules plugins`.
- *Alternative*: keep the bundled JDK. It is the "supported" combination upstream, but it means autoPatchelf over a whole JDK and a JDK outside nixpkgs security updates. Rejected.

### D3: autoPatchelf the native code, disable ML at runtime

- `autoPatchelfHook` with `stdenv.cc.cc.lib` and `zlib` patches `lib/platform/*` and the ML platform binaries, which carry their own `lib/` via RPATH.
- The zammad node additionally sets `xpack.ml.enabled: false`. Zammad does not use ML, and this avoids the native controller process and its memory use.
- If an ML binary has a dependency nixpkgs cannot satisfy, it is listed explicitly in `autoPatchelfIgnoreMissingDeps` and documented, rather than ignoring everything.

### D4: Wiring in `service-zammad.nix`

```nix
services.elasticsearch = {
  enable = true;
  package = elasticsearchPackage;   # pkgs.callPackage ../../../pkgs/elasticsearch/package.nix { }
  single_node = false;              # avoid the ES7-only gateway.auto_import_dangling_indices
  extraConf = ''
    discovery.type: single-node
    xpack.security.enabled: false
    xpack.ml.enabled: false
    http.max_content_length: 400mb
  '';
  # plugins: none; ingest-attachment is bundled since 8.4
};
```

`listenAddress` stays at the module default `127.0.0.1`. The custom `logging` block is kept.

- *Why `single_node = false` plus `extraConf`*: this is the only way to get single-node discovery without the removed setting, without forking the upstream module.

### D5: nginx locations

`/` uses `recommendedProxySettings = true` (Host, X-Real-IP, X-Forwarded-For, X-Forwarded-Proto). `/cable` goes to the web port with `proxyWebsockets = true`, and `/ws` goes to `services.zammad.websocketPort` with `proxyWebsockets = true`. Ports are read from `config.services.zammad.{port,websocketPort}` instead of a hardcoded `3000`. This mirrors the upstream module's `nginx.configure` vhost, which we can't use because it hardcodes no ACME and its own domain option.

### D6: Zammad 7.2.2 bump

- `nix run .#zammad.updateScript -- 7.2.2 ./pkgs/zammad`.
- Replace `pnpm_10` with `pnpm_11` in `package.nix` (argument, `nativeBuildInputs`, `fetchPnpmDeps.pnpm`).
- Refresh `pnpmDeps.hash` via `lib.fakeHash`.
- Format `gemset.nix` with `nixfmt` to keep the file style of the previous commit.
- `sass-embedded` 1.103.1 (new in 7.2.2's lockfile) breaks nixpkgs' `defaultGemConfig` for it. That config drops the `cli.rb` task's `dart-sass` prerequisite so nothing is downloaded, but since 1.103 that prerequisite is also what creates `ARCHDIR`. The recipe passes `gemConfig = defaultGemConfig // { sass-embedded = ...; }`, which keeps the upstream patch and adds `mkdir_p ARCHDIR` to the `cli.rb` task with `--replace-fail`, so the override fails loudly once upstream changes. Not fixed in nixpkgs-unstable either. The generated `cli.rb` runs nixpkgs' `dart-sass`.

### D7: VM test `tests/zammad-vm.nix`

- `pkgs.testers.runNixOSTest`, one node with 4 GB RAM.
- The node imports the real `modules/nixos/services/service-zammad.nix` and `service-nginx.nix` (hosts enable nginx through `elastinix.services.nginx`; the zammad module only adds its vhost) (stub `tfvars` via `node.specialArgs`), with a local `services.postgresql` that ensures user and database `zammad`, a password file, and a secret key file.
- ACME and forceSSL are `mkForce false` on the vhost, since there is no CA in the VM. `nixpkgs.config.allowUnfreePredicate` allows the vendored Elasticsearch.
- Script:
  1. Wait for `elasticsearch`, then assert that `curl :9200` reports `8.19` and `_nodes/plugins` lists the `ingest-attachment` module.
  2. Wait for `zammad-web`, then assert the welcome page through nginx on port 80.
  3. Assert the `/ws` and `/cable` upgrade path through nginx answers `101` (a WebSocket handshake with curl).
  4. Run `zammad run rails r "Setting.set('es_url','http://127.0.0.1:9200')"`, then `zammad run rake zammad:searchindex:rebuild`, which must succeed.
- It is exposed in `flake.nix` `checks` next to the existing VM tests (Linux only).
- The vhost is `zammad.example.com`, Zammad's default `fqdn`, which ActionCable accepts as origin on a fresh database.
- The builder here has no KVM, so the VM runs under TCG. `zammad-web`'s `TimeoutStartSec` is raised to 7200 s on the test node only. Its preStart seeds the database on first start, and a seed killed by the upstream 20-minute timeout is never retried ("Database already has data, skipping seed"). Test timeouts are sized for TCG.

## Risks / Trade-offs

- [Elasticsearch 8 refuses an unknown or removed setting coming from somewhere else in the module] → The VM test boots the real module. A config error means no `curl :9200` and a failing test.
- [The upstream module's custom `logging` (console only) lacks appenders ES 8 expects] → Covered by the VM test. If ES 8 needs more, fall back to the package's `log4j2.properties` by dropping our override.
- [ML native binaries fail autoPatchelf] → D3: explicit ignore list, and ML disabled at runtime.
- [Heap auto-sizing (half of RAM) competes with Zammad on small hosts] → This is the same behaviour as 7.17 today (auto heap since 7.11), so it is not a regression. The runbook names `services.elasticsearch.extraJavaOptions = [ "-Xms1g" "-Xmx1g" ]` as the knob.
- [No downgrade path after start, for either Zammad (migrations) or Elasticsearch (index metadata)] → Runbook: database dump plus an Elasticsearch data directory backup (or a fresh one, since the index is rebuilt from the database) before switching.
- [Unfree license] → The same `elastic20` license as the 7.17 package hosts already allow. The test node uses a predicate to allow exactly this package.

## Migration Plan

Runbook in `docs/services/zammad.md`:

1. Push `.#zammad` and `.#elasticsearch` to attic.
2. Dump the Zammad database (`elastinix.services.psqldump`, or `pg_dump` by hand).
3. Stop Elasticsearch and move `/var/lib/elasticsearch` aside. A fresh directory is simplest, since the index is rebuilt from the database.
4. Re-pin elastinix and deploy. Zammad runs its migrations on start.
5. `zammad run rake zammad:searchindex:rebuild`.
6. Check the Zammad settings `http_type = https` and `fqdn = zammad.<domain>` (7.2 WebSocket origin check), and the health check (import mode).

Rollback: restore the database dump and the old Elasticsearch data directory, and re-pin elastinix to before this change.
