## ADDED Requirements

### Requirement: Per-service package sourcing from nixpkgs-unstable
The system SHALL source the Documenso package and its Playwright browser driver per-service from the `nixpkgs-unstable` flake input using the stock, unmodified packages, without installing a module-global `nixpkgs.overlays` override. Host-wide package attributes SHALL remain on the pinned channel for all other consumers on the host.

#### Scenario: Documenso sourced from the unstable input
- **WHEN** the documenso service is enabled and its `package` option is left at its default
- **THEN** the service SHALL use `documenso` from the `nixpkgs-unstable` input
- **AND** host-wide `pkgs.documenso` SHALL remain the version provided by the pinned platform channel

#### Scenario: Playwright driver sourced from the same input as Documenso
- **WHEN** the build-time Playwright browser bridge is constructed
- **THEN** it SHALL draw the browser driver from the same `nixpkgs-unstable` input that provides Documenso
- **AND** the chromium-headless-shell revision Documenso expects and the revision the driver ships SHALL originate from a single mutually-consistent release

#### Scenario: No host-wide package replacement
- **WHEN** another module or operator on the same host references `pkgs.documenso` or `pkgs.playwright-driver`
- **THEN** those references SHALL resolve to the pinned platform channel, unaffected by the documenso service

### Requirement: Stock Documenso package served from the binary cache
The system SHALL use the Documenso package without derivation-altering overrides (no `overrideAttrs`), so its output hash matches the upstream build and the package is fetched prebuilt from the binary cache rather than compiled locally.

#### Scenario: Prebuilt package used
- **WHEN** the documenso service is built on a host with binary-cache access
- **THEN** the Documenso package SHALL be substituted from the binary cache
- **AND** the local pnpm/Node build SHALL NOT run for the Documenso derivation

### Requirement: Accepted license-write EROFS behavior
The system SHALL treat the boot-time license-cache write failure as expected and non-fatal, and SHALL document it, rather than patching the package to suppress it.

#### Scenario: License check succeeds despite failed cache write
- **WHEN** the documenso service starts and its license client attempts to write `.documenso-license.json` into the read-only Nix store
- **THEN** the write SHALL fail with a non-fatal `EROFS` log line
- **AND** the license check SHALL still complete with community-edition status (`NOT_FOUND`)
- **AND** the service SHALL start and operate normally, including PDF signing and rendering

#### Scenario: Behavior documented for operators
- **WHEN** an operator reads the documenso service documentation
- **THEN** the documentation SHALL state that the EROFS license-write log line is expected and harmless
