# zammad-elasticsearch Specification

## Purpose

Defines the Elasticsearch 8 package elastinix provides and how `elastinix.services.zammad` runs it as a local, single-node search backend that satisfies Zammad's supported Elasticsearch range.

## Requirements

### Requirement: Vendored Elasticsearch 8 package

Elastinix SHALL provide an Elasticsearch package at a version within Zammad's supported range (≥ 8.15 and < 10), built from the upstream Elastic release artifacts for `x86_64-linux` and `aarch64-linux`. It SHALL NOT depend on the `elasticsearch` attribute of any nixpkgs input.

#### Scenario: Version inside Zammad's supported range

- **WHEN** the vendored Elasticsearch package is evaluated
- **THEN** its version is at least 8.15.0 and lower than 10

#### Scenario: Linux only

- **WHEN** the flake is evaluated for a darwin system
- **THEN** no `elasticsearch` package output exists for that system

### Requirement: Compatible with the NixOS elasticsearch module

The vendored package SHALL run under the upstream `services.elasticsearch` module unchanged. It SHALL use the `ES_HOME` that module sets (its data directory) and a Java runtime from nixpkgs, so no writable files are expected inside the package.

#### Scenario: Service starts from the data directory

- **WHEN** `services.elasticsearch.package` is the vendored build and the service starts
- **THEN** Elasticsearch answers on its HTTP port with a version number of the vendored release
- **AND** its data and logs are under `services.elasticsearch.dataDir`

### Requirement: Flake package output for Elasticsearch

The flake SHALL expose the vendored build as `packages.<system>.elasticsearch` for `x86_64-linux` and `aarch64-linux`, so it can be built and pushed to a binary cache on its own.

#### Scenario: Build directly

- **WHEN** an operator runs `nix build .#elasticsearch` on x86_64-linux
- **THEN** the vendored Elasticsearch package is built

### Requirement: Zammad service runs the vendored Elasticsearch

When `elastinix.services.zammad` is enabled, `services.elasticsearch.package` SHALL be the vendored build. It SHALL be set inside the zammad module only, so `pkgs.elasticsearch` is unchanged for other modules.

#### Scenario: Zammad host gets Elasticsearch 8

- **WHEN** a host enables `elastinix.services.zammad`
- **THEN** `services.elasticsearch.package.version` is the vendored 8.x version
- **AND** `pkgs.elasticsearch.version` is still the nixpkgs version

### Requirement: Local single-node configuration

The Elasticsearch node of the zammad service SHALL listen on loopback only, run as a single-node cluster, and have xpack security and machine learning disabled. It SHALL NOT receive settings that Elasticsearch 8 rejects, such as `gateway.auto_import_dangling_indices`.

#### Scenario: Rendered configuration is Elasticsearch 8 compatible

- **WHEN** the zammad service is enabled
- **THEN** the rendered `elasticsearch.yml` contains `discovery.type: single-node`, `xpack.security.enabled: false` and `xpack.ml.enabled: false`
- **AND** it does not contain `gateway.auto_import_dangling_indices`

#### Scenario: Not reachable from the network

- **WHEN** the zammad service is enabled
- **THEN** Elasticsearch listens on `127.0.0.1` only

### Requirement: Attachment ingest without plugins

Attachment content indexing SHALL use the `ingest-attachment` module bundled with Elasticsearch 8. The zammad service SHALL NOT install Elasticsearch plugins.

#### Scenario: No plugins configured

- **WHEN** the zammad service is enabled
- **THEN** `services.elasticsearch.plugins` is empty
- **AND** the running node reports the `ingest-attachment` module

### Requirement: Zammad accepts the search backend

A Zammad host built from elastinix SHALL pass Zammad's own Elasticsearch version check. This is verified by an automated VM test that rebuilds the search index.

#### Scenario: Search index rebuild succeeds

- **WHEN** Zammad's `es_url` points at the local node and `zammad:searchindex:rebuild` runs
- **THEN** the task completes successfully, without `Version ... of configured elasticsearch is not supported`
