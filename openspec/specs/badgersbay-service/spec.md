# badgersbay-service Specification

## Purpose
This specification defines what the badgersbay NixOS module configures and how
the server is started. The module owns the shape - which files the service is
given and how it is launched - while agenix owns the values: the API tokens,
the dashboard password and the asset register are delivered as secrets, and the
module receives only their paths.

## Requirements

### Requirement: Deliver the asset register as a secret

The module SHALL accept a path to the asset register and SHALL pass it to the
server, so the register can be delivered as an agenix secret rather than placed
in a repository or in the generated configuration.

#### Scenario: Register configured
- **WHEN** `assetRegisterFile` names a file
- **THEN** the service is started with `--asset-register` pointing at it

#### Scenario: Register not configured
- **WHEN** `assetRegisterFile` is not set
- **THEN** no `--asset-register` argument is passed, and the host runs as it
  did before the option existed

#### Scenario: Delivered as a secret
- **WHEN** the register is delivered through agenix
- **THEN** the module receives only its path, never its contents, as it does
  for the API tokens and the dashboard password

### Requirement: Start the server with the files it needs

The service SHALL be started with the configuration, the token file and the
dashboard password file, and with the asset register when one is configured.

#### Scenario: Required files always passed
- **WHEN** the service starts
- **THEN** `--config`, `--token-file` and `--dashboard-password-file` are passed

#### Scenario: A register the server rejects
- **WHEN** the register contains a duplicate active serial, an unknown platform
  class or an unparseable date
- **THEN** the server refuses to start, because a compliance figure built on a
  register that cannot be trusted cannot be trusted either
