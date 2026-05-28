## Why

Recurring compliance and reporting tickets currently need to be created manually in Jira. As the number of clients and check types grows, a generic scheduled service is needed that automatically creates the right tickets at the right time — without per-ticket scripting or manual intervention.

## What Changes

- Add new NixOS service module `service-jiraticketcreate.nix` under `elastinix.services.jiraticketcreate`
- Service consumes the `jiraticketcreate` CLI tool as a flake input
- Module-level options: `jiraUrl`, `jiraUser` (required)
- `checkTypes` attrset defines reusable ticket templates: `frequency`, `titleTemplate`, `description`, `issueType` (default `"Task"`), `dueDateOffsetDays` (default `0`)
- `clients` attrset defines per-client config: `board`, `checks`, `tokenSecretPath` (agenix secret with raw API token), optional `jiraUrl`/`jiraUser` overrides
- NixOS module generates systemd timer + oneshot service per client×check-type combination, named `jiraticketcreate-<client>-<checkType>`
- Frequency logic (e.g. "first working day of quarter") lives in the systemd service script, not in the CLI tool
- Jira URL and user are plain NixOS options; only the API token is stored in an agenix secret

## Capabilities

### New Capabilities

- `jiraticketcreate-service`: NixOS module that schedules Jira ticket creation per client and check type, with DynamoDB-backed idempotency and systemd timer-based scheduling

### Modified Capabilities

- none

## Impact

- New file: `modules/nixos/services/service-jiraticketcreate.nix`
- New flake input: `jiraticketcreate` (this repo)
- Agenix secret per client containing raw API token (`tokenSecretPath`)

## Out of Scope / Future Considerations

- **Extended frequency model**: The current `frequency` option accepts a fixed set of named values (`first_working_day_of_month`, `first_working_day_of_quarter`, `first_working_day_of_week`). For more specific scheduling (e.g. "2nd Thursday of the month"), the option should be extended to a submodule with parameters:
  ```nix
  frequency = {
    type    = "nth_weekday_of_month";
    n       = 2;
    weekday = "thursday";
  };
  ```
  This pattern and its supported types SHALL be documented in `docs/services/jiraticketcreate.md`.
