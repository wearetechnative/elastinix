# Spec Delta

## Purpose

Defines a uniform `source` option for elastinix services that vendor their own package, so operators can choose per host between the elastinix-pinned upstream build, the stock nixpkgs build and the nixpkgs-unstable build.

## ADDED Requirements

### Requirement: Source option on vendored-package services

`elastinix.services.vaultwarden` and `elastinix.services.zammad` SHALL each expose an option `source` of type `lib.types.enum [ "pinned" "nixpkgs" "unstable" ]`.

#### Scenario: Invalid value rejected

- **WHEN** a host sets `elastinix.services.zammad.source = "master"`
- **THEN** evaluation fails with a type error listing the allowed values

### Requirement: Per-service default source

The default of `source` SHALL be `"nixpkgs"` for `elastinix.services.vaultwarden` and `"pinned"` for `elastinix.services.zammad`.

#### Scenario: Vaultwarden defaults to nixpkgs

- **WHEN** a host enables `elastinix.services.vaultwarden` without setting `source` or `package`
- **THEN** `services.vaultwarden.package` is `pkgs.vaultwarden` from the main nixpkgs input

#### Scenario: Zammad defaults to pinned

- **WHEN** a host enables `elastinix.services.zammad` without setting `source` or `package`
- **THEN** `services.zammad.package` is the vendored build at the version from `pkgs/zammad/source.json`

### Requirement: Pinned source

With `source = "pinned"`, the selected package SHALL be the elastinix build fetched from the upstream GitHub repository at the revision recorded in `pkgs/<name>/source.json`, independent of the `nixpkgs` and `nixpkgs-unstable` inputs.

#### Scenario: Pinned vaultwarden

- **WHEN** a host sets `elastinix.services.vaultwarden.source = "pinned"`
- **THEN** the running Vaultwarden has the version recorded in `pkgs/vaultwarden/source.json`

#### Scenario: Pinned zammad

- **WHEN** a host sets `elastinix.services.zammad.source = "pinned"`
- **THEN** the running Zammad has the version recorded in `pkgs/zammad/source.json`

### Requirement: Nixpkgs source

With `source = "nixpkgs"`, the selected package SHALL be the attribute of the same name from the main `nixpkgs` input of the host (`pkgs.vaultwarden` or `pkgs.zammad`), unmodified.

#### Scenario: Stock nixpkgs zammad

- **WHEN** a host sets `elastinix.services.zammad.source = "nixpkgs"`
- **THEN** `services.zammad.package` is `pkgs.zammad`

### Requirement: Unstable source

With `source = "unstable"`, the selected package SHALL be the attribute of the same name from the `nixpkgs-unstable` flake input of elastinix, for the host platform, unmodified. No module-global overlay SHALL be used.

#### Scenario: Unstable vaultwarden

- **WHEN** a host sets `elastinix.services.vaultwarden.source = "unstable"`
- **THEN** `services.vaultwarden.package` is the `vaultwarden` attribute of the `nixpkgs-unstable` input
- **AND** `pkgs.vaultwarden` as seen by other modules is unchanged

### Requirement: Package option overrides source

The `package` option SHALL remain available. Its default SHALL be the package selected by `source`. An explicitly set `package` SHALL take precedence over `source`.

#### Scenario: Package follows source

- **WHEN** a host sets `source = "unstable"` and does not set `package`
- **THEN** `package` evaluates to the unstable build

#### Scenario: Explicit package wins

- **WHEN** a host sets `source = "pinned"` and `package = myCustomVaultwarden`
- **THEN** `services.vaultwarden.package` is `myCustomVaultwarden`

### Requirement: Minimum version warning

Each service SHALL define a minimum version: the oldest release allowed to run against its production database (Vaultwarden 1.37.2, Zammad 7.2.2). When the effective package is older, the module SHALL emit a NixOS `warnings` entry naming both versions and stating that database migrations are forward-only and a backup is required. Evaluation SHALL NOT fail.

#### Scenario: Zammad from nixpkgs is below minimum

- **WHEN** a host sets `elastinix.services.zammad.source = "nixpkgs"` and nixpkgs ships Zammad 7.1.1
- **THEN** the build prints a warning mentioning 7.1.1, 7.2.2 and the need for a backup
- **AND** the build still succeeds

#### Scenario: No warning at or above minimum

- **WHEN** a host uses Vaultwarden 1.37.4 from nixpkgs (minimum 1.37.2)
- **THEN** no minimum version warning is emitted

### Requirement: Documented source selection

Each service documentation page (`docs/services/vaultwarden.md`, `docs/services/zammad.md`) SHALL describe the `source` values and default, the version each value yields at the time of writing, how to override with `package`, the minimum version and the downgrade risk.

#### Scenario: Operator looks up how to switch source

- **WHEN** an operator reads `docs/services/vaultwarden.md`
- **THEN** it shows how to set `source = "pinned"` or `"unstable"` and what to back up before a downgrade
