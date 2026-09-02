## ADDED Requirements

### Requirement: Sampling coverage is judged per day
The in-use liveness check SHALL judge coverage from the daily records in the period,
counting a day as complete when observation covered the host's uptime during that
day, so a host stopped on a schedule is not mistaken for a host whose sampler has
died.

#### Scenario: Host stopped nightly by a schedule
- **WHEN** a host is stopped for part of every day and observation covered all of its uptime
- **THEN** its in-use evidence is treated as usable

#### Scenario: Sampler stopped while the host ran
- **WHEN** a daily record accounts for unobserved time while the host was running
- **THEN** that day is not counted as complete
- **AND** findings report `unknown` when too few days in the period are complete

#### Scenario: No records for the period
- **WHEN** no daily record exists for the period being reported
- **THEN** findings report `unknown` rather than `false`

#### Scenario: The judged period is recorded
- **WHEN** coverage has been judged for a host
- **THEN** the bundle records the period examined, the days examined and the days complete

## REMOVED Requirements

### Requirement: Sampling coverage is judged on observed time
**Reason**: Replaced by per-day judgement. The accumulated window it measured against
was bounded by whatever had elapsed since the last reset, so the same sample count
could be sufficient one week and insufficient the next without anything about the
host changing.

**Migration**: Consumers read completeness per day from the daily records, and the
period judged is recorded in the bundle. The fallback to elapsed time is gone,
because there is no accumulated window that can be absent.

### Requirement: Coverage compares a numerator and denominator of the same period
**Reason**: The requirement existed to stop a lifetime sample count being divided by
a freshly started window. Within one day the numerator and denominator are the same
period by construction, so the mismatch it guarded against cannot occur.

**Migration**: Consumers read per-day completeness from each daily record instead of
pairing an accumulated window with an in-window counter.
