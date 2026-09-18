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

#### Scenario: Configuration generated from settings
- **WHEN** `configFile` is not set
- **THEN** `--config` names the file rendered from `settings`

#### Scenario: Configuration supplied by the host
- **WHEN** `configFile` is set
- **THEN** `--config` names that file, which replaces the generated one whole -
  the module's defaults do not reach it

#### Scenario: Both supplied
- **WHEN** `configFile` and `settings` are both set explicitly
- **THEN** evaluation fails, because an override that silently discards
  `settings` and a `settings` that silently discards the override are both
  worse than being told to choose

### Requirement: Own the configuration structure as options

The module SHALL expose the badgersbay configuration as a structured
`settings` option rendered to YAML, so that a host can change one value without
replacing the file, and the module's defaults continue to reach hosts that do.

The option SHALL declare, at minimum, `networkport`, `storage_location`,
`compliance.enabled`, `compliance.audit_months`, `compliance.grace_weeks`,
`compliance.required_reports.mandatory`, `compliance.required_reports.one_of`
and the per-platform-class requirements
`compliance.required_reports.per_class`, and SHALL accept keys it does not
declare.

#### Scenario: One value changed
- **WHEN** a host sets `settings.compliance.audit_months`
- **THEN** the rendered configuration carries that value and the module's
  defaults for every other key

#### Scenario: Defaults reach the host
- **WHEN** the module changes a default, such as the required report type
- **THEN** a host that has not overridden `configFile` receives it on the next
  deploy, without a secret being reissued

#### Scenario: A key the module does not declare
- **WHEN** the server gains a configuration key the module has no option for
- **THEN** a host can set it through `settings` before the module knows about
  it

#### Scenario: The port the firewall opens
- **WHEN** `settings.networkport` is set to something other than `port`
- **THEN** evaluation fails, because the firewall rule and the nginx proxy
  follow `port` and the server would be listening somewhere neither reaches

### Requirement: Keep secrets out of the configuration

`settings` SHALL carry no secret values. The API tokens, the dashboard password
and the asset register SHALL remain paths to files delivered by agenix, and the
module SHALL NOT offer an option that takes their contents as a value.

#### Scenario: Rendered to the store
- **WHEN** `settings` is rendered to YAML
- **THEN** the result is a world-readable nix store path, which is acceptable
  only because nothing in it is secret

#### Scenario: The register named in the configuration
- **WHEN** `settings.compliance.asset_register` is set
- **THEN** evaluation fails, because `--asset-register` overrides the
  configuration file and the value would be silently discarded

### Requirement: Refuse a configuration that cannot work

The module SHALL fail at evaluation, with a message naming what to change, for
a secret file that cannot be delivered or cannot be read, rather than leaving
the failure to the service start.

#### Scenario: A secret in the nix store
- **WHEN** a secret option names a path in the nix store, whether written by
  `pkgs.writeText` or copied there from a path literal
- **THEN** evaluation fails, because the store is world-readable

#### Scenario: An agenix path nobody declares
- **WHEN** a secret option names a path under `age.secretsDir` that no
  `age.secrets` entry produces
- **THEN** evaluation fails, because nothing will ever write that file

#### Scenario: A secret the service cannot read
- **WHEN** a declared `age.secrets` entry is owned by root at `0400` and the
  service runs as an unprivileged user
- **THEN** evaluation fails, naming the `owner` and `mode` to set

#### Scenario: Without agenix
- **WHEN** the agenix module is not imported
- **THEN** the agenix-specific assertions are skipped and the store-path
  assertion still applies

#### Scenario: What the assertions do not prove
- **WHEN** all assertions pass
- **THEN** the secret is still not known to exist: agenix decrypts at
  activation, and the filesystem of the build host says nothing about the
  target
