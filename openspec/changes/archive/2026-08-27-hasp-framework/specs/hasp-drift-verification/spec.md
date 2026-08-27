## ADDED Requirements

### Requirement: Change in exposure is reported as an event
Because infrastructure facts are collected on the machine on a timer, the
collector itself SHALL detect change: it MUST compare each collection against the
previously published document and report which fact keys changed, with their
previous and current values.

#### Scenario: Security group attached outside the deploy path
- **WHEN** a security group is attached to the instance and the next collection runs
- **THEN** the collector reports the change naming `network.securityGroupIds` with both values
- **AND** it exits non-zero so the event can be alerted on

#### Scenario: Public IP appears
- **WHEN** a public IP address is associated with the instance
- **THEN** the change is reported naming the affected fact

#### Scenario: No change is quiet
- **WHEN** a collection produces the same values as the previous one
- **THEN** the collector exits zero and reports no change

#### Scenario: First collection is not a change
- **WHEN** the first ever collection runs and no previous document exists
- **THEN** no change is reported

### Requirement: Per-fact change timestamps are published
The document SHALL record, per fact, when its value last changed, and SHALL list
the keys that changed at the most recent collection.

#### Scenario: Unchanged fact keeps its timestamp
- **WHEN** one fact changes and another does not
- **THEN** the changed fact's timestamp is updated and the unchanged fact's is preserved

### Requirement: Verification never reconciles
The collector MUST NOT modify `hasp.json`, any triage record, or any AWS resource.
Its only outputs are the published document and its report.

#### Scenario: Nothing else is written
- **WHEN** a change is detected
- **THEN** `hasp.json` is untouched and no triage record is altered

### Requirement: A collector that cannot run must be visible
Failure to collect MUST be distinguishable from a successful collection that found
no change. An unreachable metadata service, denied permissions, or a rejected
document MUST all exit non-zero with distinct diagnostics.

#### Scenario: Unavailability is not agreement
- **WHEN** the metadata service cannot be reached
- **THEN** the collector exits non-zero rather than reporting no change

#### Scenario: A stale document is detectable by consumers
- **WHEN** collection has been failing for longer than the collection interval implies
- **THEN** `lastCollected` allows a consumer to detect it and resolve affected claims to unknown

### Requirement: Collector unit is hardened and network-restricted
The collector unit SHALL run with systemd hardening including
`ProtectSystem=strict`, `ProtectHome`, `NoNewPrivileges`, `PrivateTmp`,
`RestrictSUIDSGID` and `ProtectProc`, and SHALL be granted write access only to
its own state directory. On the `metadata` tier it SHALL additionally be
restricted to the link-local metadata address only.

#### Scenario: Hardening applied
- **WHEN** the collector unit definition is inspected
- **THEN** the listed settings are present and write access is limited to the state directory

#### Scenario: Metadata tier reaches one address only
- **WHEN** the tier is `metadata`
- **THEN** the unit denies all outbound addresses except the instance metadata address

#### Scenario: API tier cannot be address-restricted
- **WHEN** the tier is `api`
- **THEN** the address allow-list is not applied, because AWS service endpoints are not a fixed set
