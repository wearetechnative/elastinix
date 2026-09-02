# hostinfo-socket-observation Specification

## Purpose
TBD - created by archiving change hasp-framework. Update Purpose after archive.

## Requirements

### Requirement: Observe listening sockets
The sampler SHALL record listening sockets present on the host at each sample,
capturing at minimum the port, the protocol, and the address bound to.

#### Scenario: Loopback and wildcard both recorded
- **WHEN** one service listens on `127.0.0.1:5432` and another on `0.0.0.0:3333`
- **THEN** both are recorded with their respective bind addresses

#### Scenario: UDP included
- **WHEN** a service listens on a UDP port
- **THEN** the socket is recorded with its protocol

### Requirement: Classify bind address
Each observed socket SHALL carry a derived `bindClass` of `loopback`, `wildcard` or
`specific`, alongside the raw address rather than replacing it. A socket bound to
the IPv6 wildcard MUST be classified as `wildcard`, because such a socket accepts
IPv4 connections unless IPv6-only mode is set.

#### Scenario: IPv4 loopback
- **WHEN** a socket is bound to `127.0.0.1`
- **THEN** `bindClass` is `loopback`

#### Scenario: IPv6 wildcard is not treated as IPv6-only
- **WHEN** a socket is bound to `[::]`
- **THEN** `bindClass` is `wildcard`

#### Scenario: Raw address retained
- **WHEN** a socket is recorded
- **THEN** the original bind address is present in addition to `bindClass`

### Requirement: Attribute sockets to unit and user
Each observed socket SHALL be attributed to the systemd unit and the user of the
owning process where that attribution is possible, and MUST record the absence of
attribution rather than guessing.

#### Scenario: Service-owned socket
- **WHEN** the listening process belongs to a systemd service
- **THEN** the socket records that unit name and the process user

#### Scenario: Unattributable socket
- **WHEN** the listening process is not within a systemd service unit
- **THEN** the socket is recorded with an empty unit attribution

### Requirement: Record unit-to-user mapping
The document SHALL record the user each observed unit actually runs as, so that a
finding attributed to a unit can be resolved to a privilege context.

#### Scenario: Root unit identified
- **WHEN** a unit runs with no `User=` and is observed
- **THEN** the mapping records that unit as running as `root`

#### Scenario: Join with in-use observation
- **WHEN** a package is observed mapped by a unit present in the mapping
- **THEN** the privilege context of that package's execution is derivable from the same document

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

### Requirement: Staleness contract
The document SHALL publish `schemaVersion`, `intervalSeconds`, `firstSample`,
`lastSample` and `sampleCount`, so consumers can determine how much observation
backs any claim and whether sampling has lapsed.

#### Scenario: Coverage is inspectable
- **WHEN** the document is read
- **THEN** all five fields are present

#### Scenario: Gap is detectable
- **WHEN** `sampleCount` is far below what `intervalSeconds` and the window between `firstSample` and `lastSample` imply
- **THEN** a consumer can identify that sampling lapsed

### Requirement: Untrustworthy data resolves to unknown
An absent, unparseable, stale or gapped document MUST resolve to `unknown` for any
consumer decision. It MUST NOT resolve to a negative claim.

#### Scenario: Sampler stopped
- **WHEN** the sampler has not run within the staleness bound
- **THEN** socket-based claims for that host resolve to `unknown`

#### Scenario: Staleness measured against fetch time
- **WHEN** a consumer evaluates staleness of a persisted copy
- **THEN** the comparison uses the fetch time of that copy, not the current wall-clock time

### Requirement: Sampler unit must not restrict process visibility
The sampler unit MUST NOT set `ProtectProc` or `PrivateUsers`. Either setting hides
other processes, which would cause the sampler to observe nothing while still
exiting successfully.

#### Scenario: Hardening does not blind the sampler
- **WHEN** the sampler unit definition is inspected
- **THEN** neither `ProtectProc` nor `PrivateUsers` is set
- **AND** the remaining hardening settings that do not affect process visibility are applied

### Requirement: Sample counts are per sample, not per socket

A socket entry's sample count SHALL be incremented at most once per sample, regardless of how many individual sockets share that entry's key, so the count never exceeds the number of samples taken.

#### Scenario: Listener bound on both address families

- **WHEN** a service listens on `0.0.0.0:22` and `[::]:22`, producing two sockets with the same port, protocol and bind classification
- **THEN** the entry's sample count increases by one for that sample, not two

#### Scenario: Count cannot exceed samples taken

- **WHEN** the sampler has run three times with socket observation enabled
- **THEN** no socket entry reports a sample count above three

#### Scenario: Addresses still accumulate separately

- **WHEN** two sockets sharing a key are observed in one sample
- **THEN** both addresses appear in the entry's address list
- **AND** both owning units appear in its unit list

### Requirement: Ephemeral client sockets are not recorded as listeners

A UDP socket bound to a port inside the kernel's local port range SHALL be counted as a client socket rather than accumulated as a listener, so an outbound conversation is never reported as a listening service.

#### Scenario: Outbound NTP query

- **WHEN** a time daemon binds a random UDP port in the local port range to receive a reply
- **THEN** that socket does not appear in the cumulative observed set
- **AND** the sample's client-socket count includes it

#### Scenario: Cumulative set does not grow with sampling

- **WHEN** the sampler runs repeatedly on a host whose only changing sockets are ephemeral client ports
- **THEN** the number of keys in the cumulative observed set is unchanged between runs

#### Scenario: Port range is read from the kernel

- **WHEN** a sample is taken
- **THEN** the range is read from the running kernel rather than assumed
- **AND** the range in force is published alongside the socket data

#### Scenario: TCP listeners in the ephemeral range are kept

- **WHEN** a service listens on TCP in the local port range
- **THEN** it is recorded as a listener, because TCP LISTEN state is unambiguous

#### Scenario: Previously recorded phantoms are removed

- **WHEN** the cumulative set contains entries that would now classify as client sockets
- **THEN** they are deleted on the next sample rather than persisting for the life of the document
