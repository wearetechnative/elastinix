## ADDED Requirements

### Requirement: Sampling coverage is judged on observed time

The in-use liveness check SHALL compare the sample count against the time the sampler observed, not against the elapsed calendar window, so a host stopped on a schedule is not mistaken for a host whose sampler has died.

#### Scenario: Host stopped nightly by a schedule

- **WHEN** a host is stopped for part of every day and its sampler runs whenever the host is up
- **THEN** its in-use evidence is treated as usable

#### Scenario: Sampler stopped while the host ran

- **WHEN** the sampler produced no samples across a period the host was running
- **THEN** its in-use evidence is rejected and its findings report `unknown`

#### Scenario: Document predating the observed window

- **WHEN** a host's document carries no observed window
- **THEN** the elapsed window is used and the host is not rejected for the field's absence

### Requirement: Coverage compares a numerator and denominator of the same period

The coverage check SHALL use the observed window only together with the sample count taken inside it, and otherwise fall back to elapsed time with the lifetime sample count, so the ratio is never computed across mismatched periods.

#### Scenario: Observed window without an in-window count

- **WHEN** a document carries an observed window but no in-window sample count
- **THEN** the elapsed window and the lifetime sample count are used

#### Scenario: A fresh window on an established host

- **WHEN** a host with thousands of lifetime samples begins accumulating an observed window from zero
- **THEN** the ratio is not computed from the lifetime count against the fresh window

