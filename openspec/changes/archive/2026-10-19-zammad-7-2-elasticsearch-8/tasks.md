# Tasks

## 1. Elasticsearch 8 package (bean elastinix-5nzt)

- [x] 1.1 Write `pkgs/elasticsearch/es-home.patch` (keep a pre-set `ES_HOME`, derive it only when unset) and `pkgs/elasticsearch/package.nix` for 8.19.23 (x86_64 + aarch64 sha512, nixpkgs JDK 25 as default `ES_JAVA_HOME`, no bundled JDK, autoPatchelf, `elastic20` license, Linux platforms). Verify with `nix build .#elasticsearch` (after 1.2)
- [x] 1.2 Add `elasticsearch` to the Linux-only `packages` in `flake.nix`. Verify that `nix eval .#packages --apply` lists it for both Linux systems and not for darwin
- [x] 1.3 Smoke-test the build outside NixOS: with a temp `ES_HOME` (symlinked `lib`/`modules`/`plugins`) and a minimal config, `bin/elasticsearch --version` prints 8.19.23

## 2. Zammad 7.2.2 (bean elastinix-4bsd)

- [x] 2.1 Run `nix run .#zammad.updateScript -- 7.2.2 ./pkgs/zammad` and format `gemset.nix` with nixfmt. Verify that `source.json` has `"version": "7.2.2"` and rev `295796a2df0b38a579846c017383835657687a22`
- [x] 2.2 Switch `pnpm_10` to `pnpm_11` in `pkgs/zammad/package.nix` and refresh `pnpmDeps.hash` via `lib.fakeHash`. Verify that `nix build .#zammad` succeeds and `nix eval --raw .#zammad.version` prints `7.2.2`

## 3. Zammad module wiring (bean elastinix-cgym)

- [x] 3.1 In `service-zammad.nix`, set `services.elasticsearch.package` to the vendored build, `single_node = false`, and `extraConf` with `discovery.type: single-node`, `xpack.security.enabled: false`, `xpack.ml.enabled: false`, `http.max_content_length: 400mb`; drop the `ingest-attachment` plugin. Verify by eval that the package version is 8.19.23, `plugins == []`, `pkgs.elasticsearch.version` is still 7.17.27, and the rendered config has no `gateway.auto_import_dangling_indices`
- [x] 3.2 Replace the nginx `/` location with `recommendedProxySettings`, and add `/cable` (web port) and `/ws` (websocket port) with `proxyWebsockets`, using `config.services.zammad.{port,websocketPort}`. Verify by eval that the three locations, `enableACME` and `forceSSL` are present

## 4. VM test (bean elastinix-8ha6)

- [x] 4.1 Write `tests/zammad-vm.nix` per design D7 and add `zammad-vm` to the Linux `checks` in `flake.nix`. Verify that `nix eval .#checks.x86_64-linux.zammad-vm.drvPath` evaluates
- [x] 4.2 Run `nix build .#checks.x86_64-linux.zammad-vm -L`. Verify that every subtest passes: ES 8.19 with ingest-attachment, the welcome page through nginx, WebSocket upgrades on `/ws` and `/cable`, and `zammad:searchindex:rebuild` succeeding

## 5. Documentation

- [x] 5.1 Update `docs/services/zammad.md`: Elasticsearch 8 section (package, configuration, heap knob, no plugins), the nginx locations, the pnpm 11 note, and the host upgrade runbook from design (Migration Plan). Remove the "stay on 7.1.x" note. Verify that the documented `nix build`/`nix run` commands run
- [x] 5.2 Add a CHANGELOG entry (Changed, marked breaking for hosts). Verify that the links resolve

## 6. Integration

- [x] 6.1 Run `nix flake check --no-build` and rebuild the existing `kernel-hostname-vm` check to confirm nothing else regressed. Verify that both pass

## Workflow follow-up

- Archive this change, commit, and set `openspec-link` on bean elastinix-gt7k.
- Push `.#zammad` and `.#elasticsearch` to `technative:tn-infra`.
- workloads/compute3: follow the upgrade runbook (no elastinix bean).
