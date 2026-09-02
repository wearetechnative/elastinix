# daily-observation-buckets Specification

## Purpose

Bounds observation to a period someone chose. A host records what it observed during one day, seals that record when the day ends, and never touches it again — so a claim that code never ran is a claim about the month a report covers rather than about however long a document happened to accumulate.

## Requirements

### Requirement: One sealed record per host per day

A host SHALL record its observations for a single day and seal that record when the day ends, so the period a claim rests on is fixed rather than open-ended.

#### Scenario: Day in progress

- **WHEN** samples are taken during a day
- **THEN** they accumulate into that day's record

#### Scenario: Day ends

- **WHEN** the first sample of a new day is taken
- **THEN** the previous day's record is sealed and no later sample modifies it
- **AND** a new record is started for the current day

#### Scenario: Sealed records are immutable

- **WHEN** a sealed record is read
- **THEN** its contents are identical to when it was sealed

### Requirement: A record carries the day's facts, not a running total

A record SHALL contain what was observed during its own day only, so summing records over a month is meaningful and no record depends on another.

#### Scenario: In-use observations scoped to the day

- **WHEN** a package was observed executing on that day
- **THEN** the record lists it with the number of samples that saw it during that day
- **AND** a package observed only on other days is absent from this record

#### Scenario: Socket observations scoped to the day

- **WHEN** a socket was observed during that day
- **THEN** the record lists it with its port, protocol, bind classification and owning unit

#### Scenario: The prevailing profile is recorded

- **WHEN** a record is sealed
- **THEN** it names the profile hash in force during that day

#### Scenario: Infrastructure facts are recorded

- **WHEN** infrastructure facts were collected during that day
- **THEN** the record carries their values and the keys that changed during the day

### Requirement: A complete day is one where all uptime was observed

Completeness SHALL be determined by whether observation covered the time the host was running during that day, not by whether it covered twenty-four hours, so a host that is deliberately stopped is not reported as unobserved.

#### Scenario: Host running all day

- **WHEN** a host ran for the whole day and every sample was taken
- **THEN** the day is complete

#### Scenario: Host stopped by a schedule

- **WHEN** a host is stopped for part of every day and observation covered all of its uptime
- **THEN** the day is complete
- **AND** the record states the hours observed, so the shorter period is visible as a fact

#### Scenario: Sampler stopped while the host ran

- **WHEN** the host was running during a period in which no sample was taken
- **THEN** the day is incomplete
- **AND** the record states which portion was unobserved

### Requirement: A gap is attributed to downtime or to a stalled sampler

A gap between samples SHALL be attributed using the host's own uptime, because downtime and a stalled sampler are otherwise indistinguishable and only one of them leaves the day complete.

#### Scenario: Gap explained by a reboot

- **WHEN** the gap since the previous sample exceeds the threshold and the host's uptime is shorter than that gap
- **THEN** the gap is recorded as downtime and does not make the day incomplete

#### Scenario: Gap not explained by a reboot

- **WHEN** the gap exceeds the threshold and the host's uptime is longer than that gap
- **THEN** the gap is recorded as unobserved time and the day is incomplete

#### Scenario: Attribution is recorded, not inferred later

- **WHEN** a record is sealed
- **THEN** the observed and unobserved seconds it accounts for are stated in the record
- **AND** a consumer needs no access to the host to reach the same conclusion

### Requirement: A negative claim names the days it rests on

Evidence that a package was never observed SHALL carry the number of days examined and how many of them were complete, so the strength of the claim is legible rather than implied by a sample count.

#### Scenario: Claim over a month

- **WHEN** a package was absent from every record in a period
- **THEN** the evidence states the period, the number of days examined and the number complete

#### Scenario: Incomplete coverage in the period

- **WHEN** some days in the period are incomplete
- **THEN** their count is stated alongside the claim rather than omitted
