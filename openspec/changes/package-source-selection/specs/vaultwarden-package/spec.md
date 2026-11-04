# Spec Delta

## Purpose

Defines how elastinix builds Vaultwarden (server and matching web-vault) from a pinned upstream GitHub source, so the deployed Vaultwarden version is chosen in elastinix independent of the nixpkgs pin.

## ADDED Requirements

### Requirement: Source-pinned Vaultwarden recipe

Elastinix SHALL contain a Vaultwarden recipe that builds the server from the upstream `dani-garcia/vaultwarden` GitHub repository at a pinned revision, with the PostgreSQL database backend. Bumping the `nixpkgs` input SHALL NOT change its version.

#### Scenario: Source fetched from upstream

- **WHEN** the vendored Vaultwarden package is evaluated
- **THEN** its source is fetched from `github.com/dani-garcia/vaultwarden` at the revision recorded in `pkgs/vaultwarden/source.json`

#### Scenario: Main nixpkgs bump does not change version

- **WHEN** the `nixpkgs` input is updated to a revision that ships a different Vaultwarden
- **THEN** the version of the vendored Vaultwarden package is unchanged

#### Scenario: PostgreSQL backend

- **WHEN** the vendored package is used by `elastinix.services.vaultwarden` (`dbBackend = "postgresql"`)
- **THEN** the server binary is built with the `postgresql` feature

### Requirement: Single source of truth for the Vaultwarden version

The pin SHALL be defined in one data file `pkgs/vaultwarden/source.json` holding owner, repo, rev, hash, cargoHash and version. The package version string and the version reported in the admin panel SHALL be read from that file.

#### Scenario: Version follows source.json

- **WHEN** `source.json` contains `"version": "1.37.5"`
- **THEN** the built package reports `version = "1.37.5"`
- **AND** the admin panel shows server version 1.37.5

### Requirement: Pinned Vaultwarden version

The vendored recipe SHALL pin Vaultwarden 1.37.5 or newer, and never a version older than the minimum version of the vaultwarden service (1.37.2).

#### Scenario: Pin is at least 1.37.5

- **WHEN** the vendored Vaultwarden package is evaluated
- **THEN** its version is 1.37.5 or newer

### Requirement: Matching web-vault

The vendored package SHALL ship a web-vault whose version matches the one the pinned server release targets (for 1.37.5: `v2026.10.1`), recorded in `source.json` alongside the server pin.

#### Scenario: Web-vault matches server

- **WHEN** the vendored package's `webvault` is evaluated
- **THEN** its version is the web-vault version recorded for the pinned server release

### Requirement: Scoped to the vaultwarden service

Providing the vendored Vaultwarden build SHALL NOT change `pkgs` for any other module. No module-global overlay SHALL replace `pkgs.vaultwarden`.

#### Scenario: pkgs.vaultwarden unchanged

- **WHEN** a host enables `elastinix.services.vaultwarden`
- **THEN** `pkgs.vaultwarden` as seen by other modules still resolves to the nixpkgs attribute

### Requirement: Flake package output

The flake SHALL expose the vendored build as `packages.<system>.vaultwarden` for `x86_64-linux` and `aarch64-linux`.

#### Scenario: Build package directly

- **WHEN** an operator runs `nix build .#vaultwarden` on x86_64-linux
- **THEN** the vendored Vaultwarden package is built

#### Scenario: Not exposed on unsupported systems

- **WHEN** the flake is evaluated for a darwin system
- **THEN** no `vaultwarden` package output exists for that system

### Requirement: Tag-driven update procedure

Elastinix SHALL ship an update script that takes an explicit upstream tag and regenerates `source.json` (rev, hash, version and web-vault version) for that tag. The procedure, including refreshing `cargoHash` and the web-vault hash, SHALL be documented in `docs/services/vaultwarden.md`.

#### Scenario: Update to a chosen tag

- **WHEN** an operator runs the update script with tag `1.37.5`
- **THEN** `source.json` pins the `1.37.5` revision and hash with `"version": "1.37.5"`

#### Scenario: Missing tag argument

- **WHEN** the update script is run without a tag
- **THEN** it prints usage and exits non-zero without modifying any file
