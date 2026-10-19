# Spec Delta

## Purpose

Defines how elastinix builds and provides the Zammad package from a pinned upstream GitHub source. The Zammad version deployed by `elastinix.services.zammad` is then chosen in elastinix, independent of the main nixpkgs pin.

## ADDED Requirements

### Requirement: Source-pinned Zammad recipe

Elastinix SHALL contain its own Zammad package recipe that builds Zammad from the upstream `zammad/zammad` GitHub repository at a pinned revision. Building it SHALL NOT depend on the `zammad` attribute of any nixpkgs input.

#### Scenario: Recipe builds without the nixpkgs zammad attribute

- **WHEN** the vendored Zammad package is evaluated
- **THEN** its source is fetched from `github.com/zammad/zammad` at the revision recorded in the elastinix repository
- **AND** no `pkgs.zammad` from any nixpkgs input is referenced

#### Scenario: Main nixpkgs bump does not change Zammad version

- **WHEN** the `nixpkgs` input of elastinix is updated to a revision that ships a different Zammad version
- **THEN** the version of the vendored Zammad package is unchanged

### Requirement: Single source of truth for the Zammad version

The Zammad version and source pin SHALL be defined in one data file (`source.json`) holding owner, repo, rev, hash, fetchSubmodules and version. The package version string SHALL be read from that file, not duplicated in the recipe.

#### Scenario: Version follows source.json

- **WHEN** `source.json` contains `"version": "7.1.3"`
- **THEN** the built package reports `version = "7.1.3"`

### Requirement: Initial Zammad version

The first vendored recipe SHALL pin Zammad 7.1.3, the version currently deployed on compute3 through the `update-zammad` branch. Adopting it must cause neither a downgrade nor a data migration.

#### Scenario: Initial pin matches deployed version

- **WHEN** this change is applied
- **THEN** the vendored package builds Zammad 7.1.3

### Requirement: Default package of the zammad service

The default of `elastinix.services.zammad.package` (type `lib.types.package`) SHALL be the vendored Zammad build. Consumers SHALL still be able to override the option with any other package.

#### Scenario: Default uses vendored build

- **WHEN** a host enables `elastinix.services.zammad` without setting `package`
- **THEN** `services.zammad.package` is the vendored Zammad build at the version from `source.json`

#### Scenario: Consumer override is respected

- **WHEN** a host sets `elastinix.services.zammad.package = pkgs.zammad`
- **THEN** that package is used instead of the vendored build

### Requirement: Scoped to the zammad service

Providing the vendored Zammad build SHALL NOT change `pkgs` for any other module. No module-global overlay SHALL replace `pkgs.zammad`.

#### Scenario: pkgs.zammad unchanged for other modules

- **WHEN** a host enables `elastinix.services.zammad`
- **THEN** `pkgs.zammad` as seen by other modules still resolves to the nixpkgs attribute

### Requirement: Flake package output

The flake SHALL expose the vendored build as `packages.<system>.zammad` for `x86_64-linux` and `aarch64-linux`, so it can be built and pushed to a binary cache without evaluating a host.

#### Scenario: Build package directly

- **WHEN** an operator runs `nix build .#zammad` on x86_64-linux
- **THEN** the vendored Zammad package is built

#### Scenario: Not exposed on unsupported systems

- **WHEN** the flake is evaluated for a darwin system
- **THEN** no `zammad` package output exists for that system

### Requirement: Tag-driven update procedure

Elastinix SHALL ship an update script that takes an explicit upstream tag and regenerates `source.json` (including `version`) and `gemset.nix` for that tag. The procedure, including refreshing the pnpm dependency hash, SHALL be documented in `docs/services/zammad.md`.

#### Scenario: Update to a chosen tag

- **WHEN** an operator runs the update script with tag `7.1.4`
- **THEN** `source.json` pins the `7.1.4` revision and hash with `"version": "7.1.4"`
- **AND** `gemset.nix` matches that tag's `Gemfile.lock`

#### Scenario: Missing tag argument

- **WHEN** the update script is run without a tag
- **THEN** it prints usage and exits non-zero without modifying any file
