## Context

The `service-jiraticketcreate` module generates systemd timer + oneshot service pairs for recurring Jira ticket creation. Currently the checkType submodule has two independent scheduling options:

- `frequency`: an enum selecting a bash function pair (`is_trigger_day`, `get_current_period`) inlined into the ExecStart script; the systemd timer always fires `daily`
- `timerCalendar`: a free-form systemd `OnCalendar` string, default `"daily"`

These are architecturally different mechanisms for the same concern (when to run), but are currently orthogonal options that can be combined in meaningless ways (e.g. `every_working_day` + `OnCalendar = "monthly"`).

## Goals / Non-Goals

**Goals:**
- Replace `frequency` and `timerCalendar` with a single `schedule` option
- Make the two scheduling strategies mutually exclusive by type
- Preserve all existing structured frequency values (`first_working_day_of_month`, `first_working_day_of_quarter`, `first_working_day_of_week`, `every_working_day`)
- Allow raw systemd calendar expressions via `{ calendar = "..."; }`
- Keep the module internally simple — no new runtime dependencies

**Non-Goals:**
- Adding new structured frequency values (separate change if needed)
- Supporting public holiday awareness
- Bidirectional or stateful scheduling

## Decisions

### Decision: `types.either` for the `schedule` option

`schedule` is typed as `types.either (types.enum [...]) (types.submodule { options.calendar = ...; })`.

This gives:
- Clear type error when neither string nor `{ calendar }` attrset is provided
- No need for a discriminator field or runtime `lib.throwIf` validation
- Natural Nix syntax: string for structured, attrset for calendar

**Alternative considered**: A single `scheduleType` discriminator with conditional sub-options. Rejected — more verbose and not idiomatic Nix.

**Alternative considered**: Two nullable options with `lib.throwIf` mutual exclusion. Rejected — the constraint is invisible in the option definition and error messages are worse.

### Decision: Branch on `builtins.isString schedule` in implementation

In the `mkScript` and timer generation, `builtins.isString schedule` selects the code path:

- `true` → look up `frequencyScript.${schedule}`, inline bash functions, `OnCalendar = "daily"`
- `false` → no bash day-check (script runs unconditionally), `OnCalendar = schedule.calendar`

This avoids a pattern-match helper and keeps the logic readable at each call site.

### Decision: Calendar path omits `is_trigger_day` entirely

When `schedule` is a calendar attrset, the generated ExecStart script does not include `is_trigger_day || exit 0`. The systemd timer expression IS the schedule — adding a bash guard would be redundant and confusing.

## Risks / Trade-offs

- **Breaking change** → All existing configurations must update `frequency`/`timerCalendar` to `schedule`. Mitigation: clear migration note in docs and CHANGELOG.
- **`types.either` error messages** can be verbose in Nix when neither branch matches. Mitigation: the option description clearly states both valid forms.
- **`get_current_period` on calendar path** returns the current date (`%Y-%m-%d`). For calendar-scheduled tickets the period string in `titleTemplate` will be the run date, which is semantically correct.

## Migration Plan

1. Update `modules/nixos/services/service-jiraticketcreate.nix`:
   - Remove `frequency` and `timerCalendar` options
   - Add `schedule` with `types.either`
   - Update `mkScript` and timer generation to branch on `builtins.isString schedule`
2. Update `docs/services/jiraticketcreate.md`: replace options table entries and examples
3. Update CHANGELOG under `## NEXT VERSION`

Rollback: revert the module file; no infrastructure state is affected.

## Open Questions

None — design is fully resolved from the exploration session.
