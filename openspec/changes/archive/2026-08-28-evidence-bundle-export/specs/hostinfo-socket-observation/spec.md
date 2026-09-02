## ADDED Requirements

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

