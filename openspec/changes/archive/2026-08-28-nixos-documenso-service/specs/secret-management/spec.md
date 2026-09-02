## ADDED Requirements

### Requirement: All secrets via file paths
The module SHALL accept file paths for all sensitive values via *File options.

#### Scenario: agenix integration
- **WHEN** user provides config.age.secrets.*.path as *File options
- **THEN** module reads secrets from agenix-decrypted files at runtime

#### Scenario: Secrets never in Nix store
- **WHEN** module generates environment file
- **THEN** secret values are read from files and never appear in /nix/store

### Requirement: Runtime secret loading
The module SHALL load secrets at service start time, not build time.

#### Scenario: Environment generation
- **WHEN** documenso-env.service runs
- **THEN** secrets are read from files and written to /var/lib/documenso/.env

#### Scenario: Environment file security
- **WHEN** .env file created
- **THEN** file has mode 0600 and only documenso user can read
