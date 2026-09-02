## ADDED Requirements

### Requirement: Module provides services.documenso namespace
The module SHALL expose configuration under `services.documenso` following NixOS conventions.

#### Scenario: Basic enablement
- **WHEN** user sets `services.documenso.enable = true`
- **THEN** Documenso service is configured and started via systemd

#### Scenario: Configuration validation
- **WHEN** required options are missing (e.g., publicUrl, passwordFile)
- **THEN** NixOS evaluation fails with clear error message

### Requirement: Module uses pkgs.documenso from nixpkgs
The module SHALL use the existing `pkgs.documenso` package from nixpkgs (v1.12.6).

#### Scenario: Package override support
- **WHEN** user provides custom `services.documenso.package`
- **THEN** module uses that package instead of default

#### Scenario: Package wrapper execution
- **WHEN** service starts
- **THEN** package wrapper runs migrations and starts Node.js server

### Requirement: Module generates environment configuration
The module SHALL generate `.env` file in state directory from Nix configuration.

#### Scenario: Environment file creation
- **WHEN** service starts
- **THEN** systemd oneshot service generates `/var/lib/documenso/.env` with all variables

#### Scenario: Environment file permissions
- **WHEN** environment file is created
- **THEN** file has mode 0600 and is owned by documenso user
