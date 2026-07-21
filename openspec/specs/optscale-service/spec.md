# optscale-service Specification

## Purpose
TBD - created by archiving change optscale-service. Update Purpose after archive.
## Requirements
### Requirement: The OptScale appliance runs from one elastinix service switch

The system SHALL provide `elastinix.services.optscale.enable` that, when true, runs the full OptScale appliance (substrate, configurator, all services, and the ngui UI) on the host via `optscale-nixified`'s appliance module. When disabled, no OptScale component SHALL run and the machine's package set SHALL be unaffected.

#### Scenario: Enabling the service runs OptScale

- **WHEN** a machine sets `elastinix.services.optscale.enable = true` with a valid `secretsFile`
- **THEN** the OptScale substrate, configurator, services, and UI are configured on that host

#### Scenario: Disabled leaves the machine untouched

- **WHEN** `elastinix.services.optscale.enable` is false (the default)
- **THEN** no OptScale service runs and the substrate-pins overlay / datastore allowances are not applied

### Requirement: Secrets come from an agenix-managed EnvironmentFile

The service SHALL accept `secretsFile` (a path, e.g. `config.age.secrets.optscale.path`) and wire it to `services.optscale.secrets.environmentFile`, so all OptScale secrets are supplied at runtime from an out-of-store, agenix-managed file. The documentation SHALL state the file must be readable by both the configurator (root) and minio (minio group) — `owner=root; group=minio; mode=0440` — and must contain a valid Fernet `ENCRYPTION_KEY`.

#### Scenario: Secrets wired from agenix

- **WHEN** `secretsFile = config.age.secrets.optscale.path`
- **THEN** the configurator and minio both read their credentials from that file at runtime, with no secret in the Nix store

### Requirement: The substrate is pinned and datastores permitted, scoped to the appliance

When enabled, the service SHALL apply `optscale-nixified`'s substrate-pins overlay and the `allowUnfree` (mongodb) / `allowInsecure` (minio) predicates to the host's package set, so ClickHouse/RabbitMQ match OptScale's tested versions and MongoDB/MinIO are permitted. These SHALL be gated by `enable` so machines not running OptScale are unaffected.

#### Scenario: Pins apply only when enabled

- **WHEN** the service is enabled
- **THEN** the host's `clickhouse`/`rabbitmq-server` are the OptScale-pinned versions and mongodb/minio evaluate without licence/insecure errors

### Requirement: The UI is fronted with TLS on the environment domain

The service SHALL expose the ngui UI (localhost:4000) via an nginx virtualHost `<subdomain>.<environment_domain>` (from `tfvars`) with ACME and forced SSL; backend services SHALL remain on localhost.

#### Scenario: UI reachable over HTTPS

- **WHEN** the service is enabled on a host with `tfvars.environment_domain` set
- **THEN** an nginx virtualHost terminates TLS and proxies to `http://127.0.0.1:4000`

