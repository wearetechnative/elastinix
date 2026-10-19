---
# elastinix-gt7k
title: Upgrade Zammad to 7.2.2 with Elasticsearch 8.15+
status: todo
type: feature
priority: normal
created_at: 2026-10-19T08:26:03Z
updated_at: 2026-10-19T08:26:03Z
blocked_by:
    - elastinix-do0e
---

Bump the vendored Zammad recipe (`pkgs/zammad/`, from elastinix-do0e / openspec change `zammad-source-build`) to upstream tag `7.2.2` (https://github.com/zammad/zammad/releases/tag/7.2.2). This needs Elasticsearch ≥ 8.15 first.

Origin: retargeting discussion on elastinix-do0e, 2026-10-19.

## Blocker: Elasticsearch

- Zammad 7.2 drops Elasticsearch 7. `lib/search_index_backend.rb` sets `SUPPORTED_ES_VERSION_MINIMUM = '8.15.0'` and `SUPPORTED_ES_VERSION_LESS_THAN = '10'`.
- nixpkgs (nixos-26.05 and unstable) only ships `elasticsearch` 7.17.27. There is no `elasticsearch8`/`elasticsearch9`.
- OpenSearch is rejected by the same version check: it reports 3.x, or 7.10.2 in compatibility mode.
- `service-zammad.nix` currently runs the NixOS `services.elasticsearch` default (7.17) plus the `ingest-attachment` plugin.

## Zammad 7.2.2 build notes

- Ruby stays 3.4.9 and `pnpm-lock.yaml` stays `lockfileVersion: '9.0'`.
- `packageManager: pnpm@11.25.0`, `engines: node >=24, pnpm >=11`. nixos-26.05 has `pnpm_11` (11.11.0) and nodejs 24.16. The pnpm config hook already handles pnpm 11 (`manage-package-manager-versions false`).
- Recipe changes: `pnpm_10` → `pnpm_11`, then `update.sh 7.2.2` (source.json + gemset.nix) and a new pnpm deps hash.
- Tag 7.2.2 → commit `295796a2df0b38a579846c017383835657687a22`.

## 7.2 breaking changes relevant to us (BREAKING_CHANGES.md#72)

- Elasticsearch 8.15+ required (see above).
- After the upgrade, rebuild the search index: `zammad run rake zammad:searchindex:rebuild` (new `publication_state` field). An ES major switch needs that anyway.
- Legacy WebSocket login is now authenticated from the session cookie, and only when the `Origin` matches `<http_type>://<fqdn>`. Check the Zammad settings `http_type=https` and `fqdn=zammad.<domain>`, and check websocket proxying in nginx.
- `POST /api/v1/links/add` returns 422 for existing links or self-links. Check whether slack2zammad relies on that.
- The health check reports import mode / `system_init_done=false` as an issue.

## Open questions

- How to provide ES ≥ 8.15: vendor a repackaged upstream binary under `pkgs/elasticsearch/` (like the nixpkgs 7.17 derivation, used as `services.elasticsearch.package` scoped to the zammad module), or run an OCI container.
- Which major: 8.19.x or 9.x. `ingest-attachment` has been built in since 8.4, so the plugin line can go. Local-only use needs `xpack.security.enabled: false`.
- License: ES 8.16+ is available under AGPL as well as ELv2/SSPL. Check the nixpkgs unfree handling.

## Rollout (compute3)

- Dump the database before deploying (7.1.3 → 7.2.2 runs migrations, and there is no downgrade).
- Switch ES to the new version with a fresh data dir (the index gets rebuilt), deploy Zammad 7.2.2, then run the searchindex rebuild.
