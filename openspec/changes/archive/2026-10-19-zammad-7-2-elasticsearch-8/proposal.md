# Proposal

Epic: [elastinix-gt7k — Upgrade Zammad to 7.2.2 with Elasticsearch 8.15+](../../../../.beans/elastinix-gt7k--upgrade-zammad-to-722-with-elasticsearch-815.md)

## Why

Zammad 7.2.2 fixes several security advisories, so we want to run it. But Zammad 7.2 refuses Elasticsearch older than 8.15 (`SUPPORTED_ES_VERSION_MINIMUM = '8.15.0'`, below 10). nixpkgs, both nixos-26.05 and unstable, only ships Elasticsearch 7.17.27, and that is what `elastinix.services.zammad` runs today. OpenSearch fails the same version check. Elastinix therefore has to provide an Elasticsearch 8 itself before the Zammad recipe from `zammad-source-build` can move to 7.2.2.

## What Changes

- **New package `pkgs/elasticsearch/`**: a repackaged upstream Elasticsearch **8.19.23** Linux tarball (x86_64 + aarch64), with the same approach as the nixpkgs 7.x derivation:
  - `ES_HOME` is taken from the environment.
  - It runs on the nixpkgs JDK 25 instead of the bundled JDK.
  - Native libraries and ML binaries are autoPatchelf'd.
  - It is exposed as `packages.<linux>.elasticsearch`.
- **`elastinix.services.zammad` runs Elasticsearch 8**:
  - `services.elasticsearch.package` is set to the vendored build, scoped to the zammad module.
  - The `ingest-attachment` plugin is dropped; it has been a built-in module since 8.4.
  - The local-only node runs with xpack security and ML disabled.
  - Single-node mode is set through `extraConf`, because the upstream module's `single_node` adds `gateway.auto_import_dangling_indices`, a setting removed in Elasticsearch 8.
- **Zammad bumped to 7.2.2**: `update.sh 7.2.2`, `pnpm_10` → `pnpm_11` (7.2.2 requires pnpm ≥ 11 and Node ≥ 24), and a new pnpm deps hash.
- **nginx vhost**: `/ws` and `/cable` are proxied with WebSocket upgrades, and all locations send the standard proxy headers including `X-Forwarded-Proto`. Zammad 7.2 authenticates the legacy WebSocket from the session cookie and decides the request scheme from `X-Forwarded-Proto` only.
- **New VM test** `checks.<linux>.zammad-vm`: boots the real `elastinix.services.zammad` with local PostgreSQL. It asserts that Zammad answers, Elasticsearch reports 8.19, and `zammad:searchindex:rebuild` passes Zammad's version check.
- **Docs**: an upgrade runbook for hosts (database dump, Elasticsearch switch, search index rebuild, then the Zammad 7.2 settings `http_type`/`fqdn`).

**BREAKING** for hosts that use the module: Elasticsearch moves from 7.17 to 8.19 and Zammad from 7.1.3 to 7.2.2. Neither can be downgraded once started. The upgrade runbook in `docs/services/zammad.md` must be followed.

## Capabilities

### New Capabilities

- `zammad-elasticsearch`: the Elasticsearch 8 package elastinix provides, and how the zammad service runs it (version, scope, single-node local configuration, built-in attachment ingest).
- `zammad-web-proxy`: how the zammad nginx vhost forwards HTTP, the ActionCable and legacy WebSocket endpoints, and the request scheme to Zammad.

### Modified Capabilities

- `zammad-package`: the pinned Zammad version moves from 7.1.3 to 7.2.2. The requirement that fixed the initial 7.1.3 pin is replaced by one stating the minimum pinned version.

## Impact

- **New**: `pkgs/elasticsearch/{package.nix,es-home.patch}`, `tests/zammad-vm.nix`.
- **Modified**: `pkgs/zammad/{source.json,gemset.nix,package.nix}`, `modules/nixos/services/service-zammad.nix`, `flake.nix` (packages + checks), `docs/services/zammad.md`, `CHANGELOG.md`.
- **Licensing**: Elasticsearch stays `lib.licenses.elastic20` (unfree), as with the 7.17 package hosts already run, so hosts keep needing `allowUnfree` for it.
- **Hosts (compute3)**: a one-time upgrade with a database dump, a fresh Elasticsearch data directory (or the in-place 7.17 → 8.x upgrade) and a search index rebuild. Not cached upstream: push `.#zammad` and `.#elasticsearch` to attic first.
