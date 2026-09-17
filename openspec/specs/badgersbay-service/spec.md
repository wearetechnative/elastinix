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

### Requirement: Carry a changed input into the running process

The server reads its configuration, its API tokens, its dashboard password and
its asset register once, at startup. The module SHALL declare
`restartTriggers` on the unit such that a deploy which changes any of those
files restarts the service, so that what is on disk is what the process is
serving.

For a file delivered by agenix the path is stable and the decrypted content is
not readable at evaluation, so the trigger SHALL also include the `age.secrets`
entry that produces the path - the encrypted source, whose store path follows
the ciphertext.

#### Scenario: A rotated token
- **WHEN** an agenix secret behind `tokenFile` is re-encrypted with a new token
  and deployed
- **THEN** badgersbay is restarted and accepts the new token, rather than
  continuing to accept the old one and reject the new one - two behaviours that
  both look like the system working

#### Scenario: A configuration delivered as a secret
- **WHEN** `configFile` names an agenix path, as compute2 sets it, and the
  secret's content changes
- **THEN** badgersbay is restarted, because the path the unit interpolates is
  the same string before and after the rewrite and cannot be the trigger by
  itself

#### Scenario: A configuration rendered from settings
- **WHEN** `configFile` is the file rendered from `settings` and a value changes
- **THEN** badgersbay is restarted, as the generated file is a store path that
  changes with its content

#### Scenario: A replaced asset register
- **WHEN** the register is reissued because people joined, left or swapped
  machines
- **THEN** badgersbay is restarted and the compliance figure is measured against
  the new register

#### Scenario: Restarted after the secret is written
- **WHEN** the restart is triggered by an agenix secret
- **THEN** the new content is in place before the service starts:
  `switch-to-configuration` stops the units it must restart, runs the activation
  scripts that decrypt the secrets, and only then starts them

#### Scenario: A register the server rejects, on a restart
- **WHEN** a reissued register contains a duplicate active serial, an unknown
  platform class or an unparseable date
- **THEN** the restart fails and the service stays down, which is the same
  refusal it makes at first start and is visible in the unit state - rather than
  a running service quietly measuring against the previous register

#### Scenario: Re-encrypted without an edit
- **WHEN** a secret is re-encrypted without its plaintext changing, for example
  to add a host key
- **THEN** badgersbay is restarted anyway, because age ciphertext differs on
  every encryption. A restart nobody needed costs seconds; a restart that did
  not happen is what this requirement exists for

#### Scenario: Nothing changed
- **WHEN** a deploy changes none of the four files
- **THEN** the unit is unchanged and the service is not restarted

#### Scenario: What the triggers do not cover
- **WHEN** a secret option names a file that is neither in the nix store nor
  produced by an `age.secrets` entry - a file placed on the host by hand
- **THEN** only its path can be a trigger, and a change to its content does not
  restart the service. Nothing readable at evaluation tracks that file, and the
  module does not claim otherwise
