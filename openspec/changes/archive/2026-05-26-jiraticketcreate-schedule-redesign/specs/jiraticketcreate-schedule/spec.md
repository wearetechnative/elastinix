## ADDED Requirements

### Requirement: Unified schedule option
The `checkTypes.<name>` submodule SHALL expose a single required `schedule` option typed as `types.either (types.enum [...]) (types.submodule { options.calendar = types.str; })`.

#### Scenario: Structured frequency string accepted
- **WHEN** `schedule = "first_working_day_of_month"` is configured
- **THEN** the module evaluates without error and generates a systemd service with bash day-checking logic inlined

#### Scenario: Calendar attrset accepted
- **WHEN** `schedule = { calendar = "Thu *-*-* 08:00:00"; }` is configured
- **THEN** the module evaluates without error and generates a systemd timer with `OnCalendar = "Thu *-*-* 08:00:00"`

#### Scenario: Invalid value rejected
- **WHEN** `schedule = "unsupported_value"` is configured
- **THEN** Nix evaluation fails with a type error

### Requirement: Structured frequency values
The `schedule` option SHALL accept the following string values: `"first_working_day_of_month"`, `"first_working_day_of_quarter"`, `"first_working_day_of_week"`, `"every_working_day"`.

#### Scenario: first_working_day_of_month
- **WHEN** `schedule = "first_working_day_of_month"` and the service runs on the first Monday of the month
- **THEN** `is_trigger_day` returns true and a ticket is created

#### Scenario: every_working_day on weekend
- **WHEN** `schedule = "every_working_day"` and the service runs on a Saturday
- **THEN** `is_trigger_day` returns false and the service exits 0 without creating a ticket

### Requirement: Structured schedule uses daily timer
When `schedule` is a string, the generated systemd timer SHALL use `OnCalendar = "daily"` and `Persistent = true`.

#### Scenario: Timer OnCalendar for structured frequency
- **WHEN** `schedule = "first_working_day_of_week"` is configured
- **THEN** the generated `jiraticketcreate-<instance>.timer` has `OnCalendar = daily`

### Requirement: Calendar schedule delegates to systemd
When `schedule` is an attrset with a `calendar` key, the generated systemd timer SHALL use that value as `OnCalendar`, and the ExecStart script SHALL NOT include a `is_trigger_day` guard.

#### Scenario: Timer OnCalendar from calendar expression
- **WHEN** `schedule = { calendar = "Mon-Fri *-*-* 08:00:00"; }` is configured
- **THEN** the generated timer has `OnCalendar = "Mon-Fri *-*-* 08:00:00"`

#### Scenario: No bash day-check on calendar path
- **WHEN** `schedule = { calendar = "Mon *-*-* 09:00:00"; }` is configured
- **THEN** the ExecStart script does not contain `is_trigger_day`

## REMOVED Requirements

### Requirement: frequency option
**Reason**: Replaced by the unified `schedule` option.
**Migration**: Replace `frequency = "<value>"` with `schedule = "<value>"` — the string values are identical.

### Requirement: timerCalendar option
**Reason**: Replaced by the unified `schedule` option.
**Migration**: Replace `timerCalendar = "<expr>"` with `schedule = { calendar = "<expr>"; }`.
