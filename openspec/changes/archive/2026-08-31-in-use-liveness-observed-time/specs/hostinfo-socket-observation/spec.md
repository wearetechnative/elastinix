## ADDED Requirements

### Requirement: Observed time is accumulated

The sampler SHALL accumulate the time it actually observed, so sampling coverage can be judged against time the host was running rather than time that merely elapsed.

#### Scenario: Consecutive samples

- **WHEN** two samples occur within the configured multiple of the interval
- **THEN** the elapsed time between them is added to the observed window

#### Scenario: Host was stopped between samples

- **WHEN** the gap between two samples exceeds that multiple
- **THEN** only one interval is added, because the host was not running for the remainder

#### Scenario: First sample of a document

- **WHEN** no previous sample exists
- **THEN** the observed window starts at one interval rather than zero

#### Scenario: Existing document gains the field

- **WHEN** a document written before this field existed is read
- **THEN** accumulation begins from that sample without discarding accumulated history

### Requirement: Samples are counted inside the observed window

The sampler SHALL count the samples taken within the accumulated observed window separately from the lifetime sample count, so a consumer can compare a numerator and a denominator that cover the same period.

#### Scenario: Counter advances with the window

- **WHEN** a sample credits time to the observed window
- **THEN** the in-window sample count increases by one

#### Scenario: Lifetime count is preserved

- **WHEN** the in-window counter begins at zero on an existing document
- **THEN** the lifetime `sampleCount` is unchanged and keeps advancing

### Requirement: The window accounting is versioned

The observed window and its sample count SHALL be governed by a version marker, and a document whose marker does not match the current one SHALL have both reset, so a pair that is out of step is repaired deterministically rather than by inferring whether it is consistent.

#### Scenario: Document carries a mismatched pair

- **WHEN** a document carries a window and a count that were not accumulated over the same period
- **THEN** the version marker does not match and both are reset to zero on the next sample
- **AND** the lifetime sample count and the accumulated in-use and socket history are unchanged

#### Scenario: Marker already current

- **WHEN** a document's marker matches the current version
- **THEN** the window and count continue accumulating and are not reset

#### Scenario: First sample after the reset is not read as a lapse

- **WHEN** the pair is reset and a sample is taken
- **THEN** the window is credited a single interval rather than the gap back to the previous sample
- **AND** the coverage check passes on that first sample

