---
# elastinix-5nzt
title: Package Elasticsearch 8.19 in pkgs/elasticsearch
status: completed
type: task
priority: normal
created_at: 2026-10-19T14:05:04Z
updated_at: 2026-10-19T15:22:29Z
parent: elastinix-gt7k
---

Repackage the upstream Elasticsearch 8.19.x linux tarball (x86_64 + aarch64) under pkgs/elasticsearch/, usable as services.elasticsearch.package: ES_HOME from the environment like the nixpkgs 7.x patch, nixpkgs JDK via ES_JAVA_HOME instead of the bundled JDK, autoPatchelf for native libs and ML binaries. Expose as packages.<linux>.elasticsearch.

- [x] package.nix + es-home patch
- [x] flake output
- [x] builds on x86_64-linux

## Summary of Changes

- pkgs/elasticsearch/package.nix repackages the upstream 8.19.23 Linux tarball (x86_64 + aarch64 sha512 from artifacts.elastic.co), modelled on nixpkgs' 7.x derivation.
- es-home.patch: bin/elasticsearch-env keeps a pre-set ES_HOME (the NixOS module's data dir) and defaults ES_JAVA_HOME to nixpkgs' jdk21_headless; the bundled JDK is not installed.
- autoPatchelf satisfies every native dependency (lib/platform and x-pack-ml), no ignore list needed.
- Flake output packages.<linux>.elasticsearch; perSystem pkgs allows exactly this unfree (elastic20) package.
- Smoke test with an external ES_HOME: --version reports 8.19.23 on JVM 21.0.12, the node answers HTTP, plugins are empty and ingest-attachment is a bundled module.
