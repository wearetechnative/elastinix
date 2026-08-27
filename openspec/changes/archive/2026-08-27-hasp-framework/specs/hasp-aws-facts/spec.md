## ADDED Requirements

### Requirement: Infrastructure facts are collected on the machine
The host SHALL collect its own infrastructure facts on a timer and publish them
as `hasp-aws.json`. Collection MUST NOT depend on a file produced in the
configuration repository, and the facts MUST NOT be read from Terraform state —
state records what Terraform last believed, while the machine can observe what is.

#### Scenario: Collection needs nothing from the repository
- **WHEN** a host is built with collection enabled
- **THEN** no fact file is required at evaluation time
- **AND** the build succeeds with no infrastructure facts present in the closure

#### Scenario: A change made outside the deploy path is picked up
- **WHEN** a security group is attached to the instance outside any deploy
- **THEN** the next collection reflects it without a rebuild

### Requirement: Infrastructure facts are excluded from the hashed profile
Facts that change without a rebuild MUST NOT appear in `hasp.json` and MUST NOT
contribute to `haspHash`. They SHALL be published in a separate document.

#### Scenario: Profile hash is unaffected by infrastructure change
- **WHEN** the collected security group set changes
- **THEN** `haspHash` is unchanged
- **AND** the new value appears in `hasp-aws.json`

#### Scenario: Verdict invalidation still works
- **WHEN** a verdict remembers the value of an infrastructure fact
- **THEN** that value is comparable against the current `hasp-aws.json` without consulting `hasp.json`

### Requirement: Collection tiers separate credential cost
Collection SHALL be selectable between `none`, `metadata` and `api`. The
`metadata` tier MUST require no AWS credentials or IAM permissions of any kind.
The `api` tier MAY require account-wide describe permissions, and that cost MUST
be documented at the option.

#### Scenario: Metadata tier on a host with no permissions
- **WHEN** the tier is `metadata` and the instance profile grants no describe permissions
- **THEN** collection succeeds and publishes the security group ids, subnet id and public-IP presence

#### Scenario: Metadata tier adds nothing to the closure
- **WHEN** the tier is `metadata`
- **THEN** no AWS SDK is present in the host's closure

#### Scenario: API tier extends the fact set
- **WHEN** the tier is `api`
- **THEN** ingress rules, group-referenced reachability, subnet tier, load balancer attachment and attached volumes are collected in addition

#### Scenario: Disabled by default
- **WHEN** the tier is not configured
- **THEN** it is `none`, no collector unit exists, and no document is served

### Requirement: The registry governs collected facts at runtime
The fact registry SHALL be emitted into the closure, and the collector MUST
validate its own output against it before writing. A key absent from the registry,
a value whose type disagrees with the registry, or an unsorted list MUST cause the
collector to fail without writing.

#### Scenario: Unregistered collected key rejected
- **WHEN** the collector produces a key absent from the registry
- **THEN** it exits non-zero naming the key
- **AND** the previously published document is left in place

#### Scenario: Unsorted list rejected
- **WHEN** a collected list is not in sorted order
- **THEN** the collector exits non-zero naming the fact

### Requirement: A failed collection never publishes a partial document
On any collection error the collector MUST leave the previous document in place
and exit non-zero. It MUST NOT write a document containing only the facts it
managed to obtain.

#### Scenario: Metadata service unreachable
- **WHEN** the instance metadata service does not respond
- **THEN** the collector exits non-zero
- **AND** no document is written

#### Scenario: API call fails on the api tier
- **WHEN** a describe call fails or is denied
- **THEN** the collector exits non-zero and the previous document is retained

#### Scenario: Absent facts are never implied to be safe
- **WHEN** a consumer reads a document that predates a fact being collectable
- **THEN** that fact is absent rather than present with a default value

### Requirement: The document carries its own freshness and identity
The published document SHALL include `schemaVersion`, the tier used,
`intervalSeconds`, the instance identifier, `firstCollected`, `lastCollected` and
`collectionCount`, so a consumer can tell a fresh document from a stale one.

#### Scenario: Freshness is inspectable
- **WHEN** the document is read
- **THEN** all of those fields are present

#### Scenario: Staleness measured against fetch time
- **WHEN** a consumer evaluates staleness of a persisted copy
- **THEN** the comparison uses the fetch time of that copy rather than the current wall-clock time

### Requirement: Served document is readable by the HTTP server
The document MUST be written atomically and left readable by the unprivileged user
the hostinfo server runs as.

#### Scenario: Written by a root process
- **WHEN** the collector writes the document via a temporary file and rename
- **THEN** the resulting file is world-readable and the server returns it rather than a 404

### Requirement: Subnet tier resolution handles implicit route table association
On the `api` tier, determining whether a subnet is public SHALL account for
subnets with no explicit route table association, which use the VPC main route
table.

#### Scenario: Implicitly associated subnet
- **WHEN** the instance's subnet has no explicit route table association
- **THEN** the VPC main route table is consulted
- **AND** a `0.0.0.0/0` route to an internet gateway yields `subnetTier` of `public`

#### Scenario: Isolated subnet
- **WHEN** no default route exists at all
- **THEN** `subnetTier` is `isolated`

### Requirement: Group-referenced ingress is recorded separately from internet ingress
Ingress permitted from another security group SHALL be recorded with the
referencing group and ports, distinct from ports reachable from the internet.

#### Scenario: Reachable only from a jumphost
- **WHEN** ports 22 and 3333 are permitted from a jumphost security group and nothing from `0.0.0.0/0`
- **THEN** the internet-reachable port list is empty
- **AND** the jumphost group is recorded with those ports

### Requirement: Very wide port ranges are recorded as such
A permitted range wider than a bounded expansion limit, or a rule covering all
protocols, SHALL set an explicit "all ports open" fact rather than being expanded
into an unbounded list of integers.

#### Scenario: Rule permitting every port
- **WHEN** an internet-facing rule covers all protocols or the full port range
- **THEN** the all-ports-open fact is true
- **AND** the port list is not expanded beyond the bounded limit
