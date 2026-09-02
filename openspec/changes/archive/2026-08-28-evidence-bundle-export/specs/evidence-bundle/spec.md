## Purpose

Merges every per-host scan and attack-surface artifact collected by the central scanner into one schema-versioned `evidence.json` document, so a downstream report generator can produce ISO 27001 audit evidence from a single immutable snapshot without contacting hosts or AWS.

## ADDED Requirements

### Requirement: Schema-versioned bundle document

The scanner SHALL write a bundle document containing `schemaVersion`, `runId` and `generatedAt` at its top level, so a consumer can reject a bundle it does not understand instead of mis-rendering it.

#### Scenario: Bundle identifies its schema and run

- **WHEN** a scan run completes
- **THEN** the bundle contains an integer `schemaVersion`
- **AND** `runId` is the run's UTC timestamp in `YYYY-MM-DDTHH-MM-SSZ` form
- **AND** `generatedAt` is an RFC 3339 UTC timestamp

#### Scenario: Schema version is incremented on incompatible change

- **WHEN** a field is removed or its meaning changes such that an existing consumer would misread it
- **THEN** `schemaVersion` is incremented

### Requirement: Fleet coverage accounting

The bundle SHALL record which configured hosts were collected and which were skipped, with a reason for every skip, so a report cannot present partial collection as full assurance.

#### Scenario: All hosts collected

- **WHEN** every configured host returns HTTP 200 for `packages.json`
- **THEN** `coverage.configured` lists every configured host name
- **AND** `coverage.collected` contains the same names
- **AND** `coverage.skipped` is an empty list

#### Scenario: One host unreachable

- **WHEN** a configured host named `compute3` cannot be reached for `packages.json`
- **THEN** `coverage.collected` does not contain `compute3`
- **AND** `coverage.skipped` contains an entry for `compute3` with a non-empty `reason` string
- **AND** `coverage.configured` still contains `compute3`

#### Scenario: Coverage is derived from collection outcomes

- **WHEN** the bundle is written
- **THEN** the coverage lists are derived from the run's own fetch results rather than parsed from log text

### Requirement: Per-source content hashes

The bundle SHALL record a SHA-256 digest and a fetch timestamp for every source artifact it consumed, so a rendered report can cite a digest instead of reproducing full inventories.

#### Scenario: Digests recorded per host

- **WHEN** `packages.json`, `inuse.json`, `hasp.json`, `hasp-aws.json` and `runtime-facts.json` are all fetched for a host
- **THEN** the host's `sources` object contains one entry per artifact
- **AND** each entry carries a `sha256` of the fetched bytes and a `fetchedAt` timestamp

#### Scenario: Profile hash exposed alongside digest

- **WHEN** `hasp.json` is fetched successfully for a host
- **THEN** the `hasp.json` source entry additionally carries the profile hash declared inside that document

#### Scenario: Absent source recorded as absent

- **WHEN** a host does not serve `hasp-aws.json`
- **THEN** the host's `sources` object either omits the `hasp-aws.json` entry or marks it as not collected
- **AND** no digest is fabricated for it

### Requirement: Per-host attack surface profile

The bundle SHALL include, for every collected host, the declared and derived facts from its HASP profile and the infrastructure facts from its AWS document, so the report can describe how each host is exposed.

#### Scenario: Profile facts present

- **WHEN** a host's `hasp.json` is collected
- **THEN** the host's `profile` object contains its declared facts and its derived facts
- **AND** each fact retains its provenance marker

#### Scenario: AWS facts merged when collected

- **WHEN** a host's `hasp-aws.json` is collected
- **THEN** the infrastructure facts it carries appear in the host's `profile`
- **AND** they remain distinguishable from declared and derived facts by provenance

#### Scenario: Profile records the HASP document's own schema version

- **WHEN** a host's `hasp.json` is collected
- **THEN** the host's `profile` records the schema version declared by that document
- **AND** it is distinct from the bundle's own `schemaVersion`

#### Scenario: Host with AWS collection disabled

- **WHEN** a host does not serve `hasp-aws.json` because AWS fact collection is off
- **THEN** the host's `profile` contains only declared and derived facts
- **AND** the bundle is still written for that host

### Requirement: Per-host network exposure

The bundle SHALL include the observed listening sockets and their bind classification for every host that serves runtime facts, so the report can distinguish loopback-only services from externally reachable ones.

#### Scenario: Sockets recorded with bind class

- **WHEN** a host's `runtime-facts.json` reports listening sockets
- **THEN** the host's `exposure` object lists each socket with its port, protocol, bind classification and owning unit

#### Scenario: Socket observation not enabled

- **WHEN** a host serves runtime facts without socket observation data
- **THEN** the host's `exposure` object is present but records that socket observation was not enabled

### Requirement: Per-host findings with in-use status

The bundle SHALL include every vulnix finding for each collected host, annotated with whether the affected package was observed in use, so the report can rank findings by real exposure.

#### Scenario: Finding annotated as in use

- **WHEN** a vulnix finding names a package that appears in the host's in-use evidence
- **THEN** the finding's `inUse` field is `true`

#### Scenario: Finding annotated as not in use

- **WHEN** a vulnix finding names a package absent from the host's in-use evidence and the in-use evidence is usable
- **THEN** the finding's `inUse` field is `false`

#### Scenario: In-use evidence missing or stale

- **WHEN** the host's in-use evidence could not be fetched or is stale
- **THEN** every finding for that host has `inUse` set to `unknown`

### Requirement: Per-host finding summary

The bundle SHALL summarise each host's findings by counting only packages that carry at least one reportable finding, so a count cited in an audit is not inflated by packages whose every CVE was excluded.

#### Scenario: Package whose every CVE is vendor-excluded

- **WHEN** vulnix flags a package but every one of its CVEs is dropped by vendor exclusion
- **THEN** `summary.packages` does not count that package
- **AND** `summary.packagesFlagged` does count it, preserving the pre-exclusion figure

#### Scenario: No exclusions apply

- **WHEN** no finding is excluded for a host
- **THEN** `summary.packages` equals `summary.packagesFlagged`

#### Scenario: Summary agrees with the findings list

- **WHEN** the bundle is read
- **THEN** `summary.packages` equals the number of distinct `package` values in that host's `findings`
- **AND** `summary.distinctCves` equals the number of distinct `cve` values in it

### Requirement: Container image findings

The bundle SHALL include trivy findings per image for hosts with Docker scanning enabled, so container and package evidence appear in one document.

#### Scenario: Images present for a scanned host

- **WHEN** trivy scanned two images on a host
- **THEN** the host's `images` list contains one entry per image, each naming the image reference and its findings

#### Scenario: Docker scanning disabled

- **WHEN** a host has Docker scanning disabled
- **THEN** the host's `images` list is empty

### Requirement: Staleness marking

The bundle SHALL mark a source as stale when its own timestamp is older than the freshness window for that artifact, so a report is never silently built on outdated facts.

#### Scenario: AWS facts older than the window

- **WHEN** a host's `hasp-aws.json` carries a collection timestamp older than the configured freshness window
- **THEN** its source entry is marked `stale: true`

#### Scenario: Fresh source not marked

- **WHEN** a source's timestamp falls inside the freshness window
- **THEN** its source entry is marked `stale: false`

### Requirement: Unusable source does not abort the run

The scanner SHALL continue building the bundle when an individual source is missing or unparseable, recording the failure rather than aborting.

#### Scenario: Malformed JSON from a host

- **WHEN** a fetched artifact is not valid JSON
- **THEN** a warning is logged and the artifact is treated as not collected
- **AND** the bundle is still written for the remaining hosts and sources

#### Scenario: Every host unreachable

- **WHEN** no configured host could be reached
- **THEN** a bundle is still written with an empty `coverage.collected` and every host listed under `coverage.skipped`

### Requirement: Bundle is written atomically

The scanner SHALL publish the bundle only once it is complete and valid JSON, so a consumer never reads a truncated document.

#### Scenario: Successful write

- **WHEN** normalization completes
- **THEN** the bundle is written to a temporary file and moved into place
- **AND** the published file is world-readable

#### Scenario: Normalization fails partway

- **WHEN** normalization raises an error before completion
- **THEN** no partial bundle replaces a previously published one
- **AND** the failure is logged and counted as an error
