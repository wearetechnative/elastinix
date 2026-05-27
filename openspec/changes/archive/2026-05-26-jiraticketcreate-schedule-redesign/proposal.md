## Why

The `service-jiraticketcreate` module currently exposes two separate options — `frequency` (an enum for bash-level day-checking) and `timerCalendar` (a raw systemd OnCalendar string) — that are conceptually alternatives, not complements. Having both creates confusion about which to use and allows contradictory combinations. A single `schedule` option with two well-defined shapes is clearer and more correct.

## What Changes

- **BREAKING**: Remove `checkTypes.<name>.frequency` option
- **BREAKING**: Remove `checkTypes.<name>.timerCalendar` option
- Add `checkTypes.<name>.schedule` option accepting either:
  - A structured frequency string (`"first_working_day_of_month"` | `"first_working_day_of_quarter"` | `"first_working_day_of_week"` | `"every_working_day"`)
  - A raw systemd calendar attrset (`{ calendar = "Thu *-*-* 08:00:00"; }`)
- Structured path: systemd timer fires daily, bash `is_trigger_day()` function decides whether to create a ticket
- Calendar path: systemd timer fires on the given expression, no bash day-check (ticket always created when service runs)

## Capabilities

### New Capabilities

- `jiraticketcreate-schedule`: Unified schedule option for checkTypes — either a structured frequency or a raw systemd calendar expression

### Modified Capabilities

- `jiraticketcreate-service`: The checkType submodule interface changes — `frequency` and `timerCalendar` replaced by `schedule`

## Impact

- `modules/nixos/services/service-jiraticketcreate.nix`: option definitions, frequencyScript lookup, timer OnCalendar generation, script assembly
- `docs/services/jiraticketcreate.md`: options table and examples updated
- All existing NixOS configurations using `frequency` or `timerCalendar` must migrate to `schedule`
