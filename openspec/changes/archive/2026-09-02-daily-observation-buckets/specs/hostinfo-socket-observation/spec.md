## MODIFIED Requirements

### Requirement: Cumulative and current socket sets
Each daily record SHALL contain the sockets observed during that day with per-entry
sample counts and last-seen timestamps, and a `current` snapshot from the most
recent sample. The set is cumulative within its day and does not carry across days.

#### Scenario: Socket closed since last observation
- **WHEN** a socket observed earlier the same day is absent from the current sample
- **THEN** it remains in that day's set with its previous count
- **AND** it is absent from the current snapshot

#### Scenario: Socket observed on an earlier day
- **WHEN** a socket was observed yesterday and not today
- **THEN** it is absent from today's record
- **AND** yesterday's sealed record still carries it

### Requirement: Negative claims use the cumulative set
A claim that a port was never externally bound SHALL be based on the union of the
daily records covering the period claimed, never on a single sample and never on the
`current` snapshot.

#### Scenario: Load-triggered listener
- **WHEN** a service binds an external socket briefly and is captured in one sample of one day
- **THEN** that day's record captures it
- **AND** a claim of "never externally bound" is not supported for that port over any period including that day

#### Scenario: Claim spanning several days
- **WHEN** a claim covers a month
- **THEN** it is evaluated against every daily record in that month

## REMOVED Requirements

### Requirement: Observed time is accumulated
**Reason**: The accumulating window existed because observation never ended. A daily
record is bounded by its own day, so the time it covers is a property of the record
rather than a running total that has to be maintained and repaired.

**Migration**: `observedWindowSeconds` is replaced by the observed and unobserved
seconds each daily record accounts for. Consumers that divided a sample count by
that window now read completeness from the record itself.

### Requirement: Samples are counted inside the observed window
**Reason**: The counter existed only so a numerator and a denominator covered the
same period. Within a single day they do so by construction.

**Migration**: `samplesInObservedWindow` is replaced by the sample count in each
daily record, which covers exactly that record's day.

### Requirement: The window accounting is versioned
**Reason**: The version marker existed to force a clean restart when the window and
its counter had drifted apart. A sealed record cannot drift, so there is nothing to
detect or repair.

**Migration**: `observedWindowEpoch` is dropped. The existing cumulative document is
discarded rather than converted; every host begins a fresh series of daily records.
