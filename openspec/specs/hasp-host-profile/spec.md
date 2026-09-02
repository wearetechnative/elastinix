# hasp-host-profile Specification

## Purpose
TBD - created by archiving change hasp-framework. Update Purpose after archive.

## Requirements

### Requirement: Module enable option
The `elastinix.hasp` module SHALL provide an `enable` boolean option, defaulting to
`false`, which when disabled produces no documents and adds no systemd units.

#### Scenario: Disabled by default
- **WHEN** a host configuration does not mention `elastinix.hasp`
- **THEN** no HASP document is generated and no unit is added

#### Scenario: Rollback without side effects
- **WHEN** `elastinix.hasp.enable` is set to `false` on a host that previously had it enabled
- **THEN** the documents are removed
- **AND** vulnix scanning, the Prometheus exporter and the in-use sampler continue unchanged

### Requirement: Static pure evaluation
`hasp.json` SHALL be produced entirely during Nix evaluation and materialise as a
single store path symlinked into `/var/lib/hostinfo/hasp.json`. The module MUST NOT
create a generator service, timer, or any runtime templating step for it.

#### Scenario: No runtime generation
- **WHEN** the system is built with `elastinix.hasp.enable = true`
- **THEN** `/var/lib/hostinfo/hasp.json` is a symlink into `/nix/store`
- **AND** no systemd unit exists whose purpose is to write it

#### Scenario: Identical across two evaluations
- **WHEN** an unchanged host configuration is evaluated twice
- **THEN** both evaluations produce the same store path

### Requirement: No build timestamp
The document MUST NOT contain a generation timestamp. Freshness SHALL be determined
by the consumer from its own fetch time.

#### Scenario: Timestamp absent
- **WHEN** `hasp.json` is read
- **THEN** it contains no `generatedAt` or equivalent field

### Requirement: Fact record structure
Every fact SHALL be an attribute set carrying `value`, `source` and `evidence`.
`source` MUST be one of `derived`, `declared`, `aws` or `observed`. `evidence` MUST
identify where the value came from: a Nix option path, an AWS resource identifier,
or the name of the person who decided it.

#### Scenario: Complete fact record
- **WHEN** a fact is emitted
- **THEN** it carries all three fields
- **AND** `source` is one of the four permitted values

#### Scenario: Missing evidence fails the build
- **WHEN** a fact is defined without `evidence`
- **THEN** evaluation fails with an assertion naming the fact key

### Requirement: Closed fact registry
Fact keys SHALL be constrained to a closed, versioned registry. An unregistered key
MUST fail the build rather than being emitted or silently dropped. Key, declared
source, and value type MUST all be checked, and the check MUST cover **every**
fact section including `fleet` — a section validated by nothing is where an
unregistered key lands unnoticed.

#### Scenario: Unregistered key rejected
- **WHEN** a configuration defines the fact key `network.publicIPAttached` while the registry contains `network.publicIpAttached`
- **THEN** evaluation fails with an assertion naming the unregistered key

#### Scenario: Fleet section checked on the same terms
- **WHEN** a fleet fact is emitted under a key absent from the fleet registry
- **THEN** evaluation fails with an assertion naming that key

#### Scenario: Declared source must match the registry
- **WHEN** a fact is emitted with a `source` differing from the one the registry records for its key
- **THEN** evaluation fails naming the fact

#### Scenario: Value type must match the registry
- **WHEN** a fact value's type differs from the type the registry records for its key
- **THEN** evaluation fails naming the fact

#### Scenario: Registry version published
- **WHEN** `hasp.json` is read
- **THEN** it declares both `schemaVersion` and `registryVersion`

### Requirement: Declared facts have no defaults
Declared facts SHALL have no default values. A missing declared fact MUST fail the
build. This applies to `environment`, `role`, `owner`, `dataClassification` and
`isJumphost`.

#### Scenario: Missing classification fails the build
- **WHEN** `elastinix.hasp.declared.dataClassification` is not set
- **THEN** evaluation fails with an assertion naming the missing declaration
- **AND** no document is produced containing a substituted value

#### Scenario: Enum value validated
- **WHEN** `elastinix.hasp.declared.environment` is set to a value outside `prod`, `nonprod`, `dev`
- **THEN** evaluation fails

### Requirement: Declared block review metadata
The declared block SHALL require `reviewedBy` and `reviewedAt`, covering the block
as a whole rather than individual facts. Both MUST be published in the document.

#### Scenario: Review metadata required
- **WHEN** `reviewedBy` or `reviewedAt` is absent
- **THEN** evaluation fails

#### Scenario: Review metadata published for alerting
- **WHEN** `hasp.json` is read
- **THEN** it contains `declaredReview` with `by` and `at`

### Requirement: Content hash over values only
The document SHALL publish `haspHash`, computed over the host facts' `value` fields
only. `evidence`, `source` and the review stanza MUST NOT affect the hash.

#### Scenario: Evidence correction does not change the hash
- **WHEN** a fact's `evidence` string is corrected but no `value` changes
- **THEN** `haspHash` is unchanged

#### Scenario: Review date does not change the hash
- **WHEN** `reviewedAt` is updated to a later date and no fact value changes
- **THEN** `haspHash` is unchanged

#### Scenario: Value change changes the hash
- **WHEN** any host fact `value` changes
- **THEN** `haspHash` changes

### Requirement: Fleet facts hashed separately
Facts with no per-host variance SHALL be carried in a `fleet` section with its own
`fleetHash`, separate from host facts and excluded from `haspHash`.

#### Scenario: Fleet change does not alter the host hash
- **WHEN** a fleet fact value changes and no host fact changes
- **THEN** `fleetHash` changes
- **AND** `haspHash` is unchanged

### Requirement: List facts are sorted
Any fact whose value is a list SHALL be sorted at construction, so that upstream
ordering changes cannot alter the hash.

#### Scenario: Unsorted list rejected
- **WHEN** a list fact is defined in unsorted order
- **THEN** evaluation fails with an assertion naming the fact key

### Requirement: No package or closure enumeration
The document MUST NOT contain package names, package versions, or an enumeration of
an upstream-defined set such as the full systemd unit list. Derived facts SHALL be
projections that answer a specific question.

#### Scenario: Deploy does not churn the hash
- **WHEN** a host is redeployed with an updated nixpkgs but no configuration change affecting registered facts
- **THEN** `haspHash` is unchanged

#### Scenario: Fact values are JSON-comparable
- **WHEN** any fact value is read
- **THEN** it is a boolean, string, integer, or a list or attribute set of those

### Requirement: Firewall facts state whether the firewall is running

The profile SHALL publish whether the host firewall is enabled, so a port allow-list can never be read as a restrictive control on a host that has no firewall.

#### Scenario: Firewall enabled

- **WHEN** `networking.firewall.enable` is true
- **THEN** `network.firewallEnabled` is `true`
- **AND** the open-port facts list the configured allowed ports

#### Scenario: Firewall disabled

- **WHEN** `networking.firewall.enable` is false
- **THEN** `network.firewallEnabled` is `false`
- **AND** the open-port facts are empty rather than listing inert configuration
- **AND** each open-port fact's evidence string states that the firewall is disabled and every port of that protocol is reachable

#### Scenario: Configured ports are inert when the firewall is off

- **WHEN** a host defines `allowedTCPPorts` but sets `networking.firewall.enable = false`
- **THEN** no consumer reading the profile can obtain a non-empty allow-list for that host

### Requirement: Firewall facts are protocol-specific

The profile SHALL record open firewall ports separately per protocol, so an observed socket carrying a protocol can be matched against the correct allow-list.

#### Scenario: TCP and UDP recorded apart

- **WHEN** a host allows TCP 443 and UDP 4242
- **THEN** `network.firewallOpenTcpPorts` contains 443 and not 4242
- **AND** `network.firewallOpenUdpPorts` contains 4242 and not 443

#### Scenario: Same port number on both protocols

- **WHEN** a host allows TCP 53 and UDP 53
- **THEN** both facts contain 53 independently
