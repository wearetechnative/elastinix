# Spec: jiraticketcreate-service

## Purpose

Defines the requirements for the NixOS module `elastinix.services.jiraticketcreate`, which automatically creates Jira tickets on a configurable schedule. The module supports multiple clients and reusable check-type templates, with daily systemd timers and frequency logic evaluated at runtime in bash.

## Requirements

### Requirement: NixOS module under elastinix.services.jiraticketcreate
The module SHALL be configurable under the `elastinix.services.jiraticketcreate` namespace with a top-level `enable` boolean.

#### Scenario: Module disabled by default
- **WHEN** `elastinix.services.jiraticketcreate.enable` is not set
- **THEN** no systemd services or timers are created

#### Scenario: Module enabled
- **WHEN** `elastinix.services.jiraticketcreate.enable = true`
- **THEN** systemd services and timers are generated for all configured client×check-type combinations

### Requirement: Check types defined once at module level
The module SHALL accept a `checkTypes` attrset where each entry defines a reusable ticket template. Required fields: `frequency`, `titleTemplate`, `description`. Optional fields: `issueType` (default `"Task"`), `dueDateOffsetDays` (default `0`, meaning due date equals the trigger date).

The `frequency` value is a string that the NixOS module reads at build time to select and inline the correct bash function into the generated systemd service script. Systemd has no knowledge of the frequency value — the systemd timer always fires daily; the bash function determines at runtime whether today is the trigger day using `date` commands.

Supported values:
- `first_working_day_of_month` — first Mon–Fri of each month
- `first_working_day_of_quarter` — first Mon–Fri of Jan/Apr/Jul/Oct
- `first_working_day_of_week` — every Monday

#### Scenario: Check type declared
- **WHEN** a check type `aws-permission-matrix` is declared with `frequency = "first_working_day_of_quarter"`
- **THEN** all clients that include it get a quarterly systemd timer for that check
- **AND** the NixOS module inlines the `first_working_day_of_quarter` bash function into the generated service script

#### Scenario: Unsupported frequency value
- **WHEN** `frequency` is set to a value not in the supported list
- **THEN** the NixOS module SHALL throw an evaluation error via `lib.throwIf`

### Requirement: Clients reference check types by name
The module SHALL accept a `clients` attrset where each entry has a `board` (Jira project key) and a `checks` list referencing check type names.

#### Scenario: Client with two checks
- **WHEN** client `iit` declares `checks = [ "aws-permission-matrix" "security-scan" ]`
- **THEN** two systemd service+timer pairs are generated: `jiraticketcreate-iit-aws-permission-matrix` and `jiraticketcreate-iit-security-scan`

#### Scenario: Client with subset of checks
- **WHEN** client `acme` declares `checks = [ "aws-permission-matrix" ]` while `security-scan` is also defined
- **THEN** only one service+timer pair is generated for `acme`

### Requirement: Due date computed at runtime from trigger date
The service script SHALL compute `due_date` as the trigger date (today, when the frequency condition is met) plus `dueDateOffsetDays` calendar days, formatted as ISO 8601 (`YYYY-MM-DD`). The computed `due_date` is written into the temp JSON config passed to the CLI.

#### Scenario: Due date with offset
- **WHEN** the service runs on 2026-04-01 and `dueDateOffsetDays = 14`
- **THEN** the temp JSON contains `"due_date": "2026-04-15"`

#### Scenario: Due date with zero offset
- **WHEN** `dueDateOffsetDays = 0`
- **THEN** `due_date` equals the trigger date

### Requirement: Daily systemd timer with frequency logic in script
Each generated instance SHALL have a systemd timer with `OnCalendar = "daily"` and `Persistent = true`. The service script SHALL evaluate whether today matches the configured frequency before proceeding.

#### Scenario: Timer fires on non-trigger day
- **WHEN** the systemd service runs and today is not the first working day of the configured period
- **THEN** the service exits 0 without creating a ticket

#### Scenario: Timer fires on trigger day
- **WHEN** the systemd service runs and today is the first working day of the configured period
- **THEN** the service calls the `jiraticketcreate` CLI with the rendered config

### Requirement: Jira URL and user configurable at module level with per-client override
The module SHALL accept `jiraUrl` and `jiraUser` string options at module level as defaults. Each client MAY override these with its own `jiraUrl` and `jiraUser` options (type `nullOr str`, default `null`). When a client override is `null`, the module-level default is used.

#### Scenario: All clients share one Jira instance
- **WHEN** `jiraUrl` and `jiraUser` are set at module level and no client sets overrides
- **THEN** all generated service scripts use the module-level values for `api.url` and `api.user`

#### Scenario: One client uses a different Jira instance
- **WHEN** a client sets `jiraUrl = "https://other.atlassian.net"` and `jiraUser = "other@mycompany.com"`
- **THEN** that client's generated service scripts use the client-level values
- **AND** all other clients continue to use the module-level defaults

### Requirement: Jira API token via agenix secret per client
Each client SHALL reference an agenix secret path via `tokenSecretPath`. The secret file SHALL contain only the raw API token. The path is passed as `api.token_file` in the JSON config passed to the CLI.

#### Scenario: Token file configured
- **WHEN** a client has `tokenSecretPath = config.age.secrets.jira-token-iit.path`
- **THEN** the generated JSON config sets `api.token_file` to that path
- **AND** the CLI reads the token directly from the file

### Requirement: Systemd hardening applied
Generated systemd services SHALL apply standard elastinix hardening options: `PrivateTmp`, `ProtectSystem = "strict"`, `NoNewPrivileges`, `ProtectHome`, `PrivateDevices`, `RestrictAddressFamilies = [ "AF_INET" "AF_INET6" ]`.

#### Scenario: Service runs with hardening
- **WHEN** a generated service starts
- **THEN** it runs with all standard hardening options active
