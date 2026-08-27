## ADDED Requirements

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
The document SHALL record both a cumulative `observed` set with per-entry sample
counts and last-seen timestamps, and a `current` snapshot from the most recent
sample.

#### Scenario: Socket closed since last observation
- **WHEN** a socket observed previously is absent from the current sample
- **THEN** it remains in the cumulative set with its previous count
- **AND** it is absent from the current snapshot

### Requirement: Negative claims use the cumulative set
A claim that a port was never externally bound SHALL be based on the cumulative
observed set, never on the current snapshot.

#### Scenario: Load-triggered listener
- **WHEN** a service binds an external socket briefly and is captured in one sample out of many
- **THEN** the cumulative set records it
- **AND** a claim of "never externally bound" is not supported for that port

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
