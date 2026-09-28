## ADDED Requirements

### Requirement: Render the garbage-collection configuration

The module SHALL render a `[garbage-collection]` section into the generated
attic server configuration, driven by options under
`elastinix.services.attic.garbage_collection`. The collector's interval SHALL be
stated explicitly rather than left to the upstream default, so that an operator
reading the generated configuration can see what the collector does without
consulting attic's source.

#### Scenario: Section is present by default

- **WHEN** a host enables `elastinix.services.attic` without configuring
  `garbage_collection`
- **THEN** the generated `checked-attic-server.toml` contains a
  `[garbage-collection]` section
- **AND** that section sets both `interval` and `default-retention-period`

#### Scenario: Operator overrides the interval

- **WHEN** `garbage_collection.interval = "1 hour"`
- **THEN** the generated configuration carries exactly that value

### Requirement: Expire cache objects that are old and unused

The module SHALL default `garbage_collection.default_retention_period` to 90
days, so that a cache which sets no retention of its own expires objects instead
of growing without limit. Setting the option to `null` SHALL render a zero
period, which disables time-based collection and restores attic's own default.

#### Scenario: Default retention applies to a cache with none of its own

- **WHEN** a cache row's `retention_period` is NULL and the module default is in
  effect
- **THEN** an object whose `created_at` is older than 90 days and whose
  `last_accessed_at` is null or older than 90 days is deleted by the collector
- **AND** its NAR and chunks are removed on a later pass, from the S3 bucket as
  well as the database

#### Scenario: Recently downloaded objects survive

- **WHEN** an object was created two years ago but its NAR was downloaded
  yesterday
- **THEN** the collector does not delete it, because deletion requires both
  timestamps to precede the cutoff

#### Scenario: Retention can be switched off

- **WHEN** `garbage_collection.default_retention_period = null`
- **THEN** the generated configuration sets `default-retention-period = "0"`
- **AND** only orphan reaping remains, which is attic's behaviour without the
  section

### Requirement: Document what counts as access

The module documentation SHALL state that `last_accessed_at` is bumped only when
a client downloads the NAR, and not when it fetches the `.narinfo`. A host that
already holds a path fetches only the narinfo, so continued use by hosts that
are already up to date does not keep a cached copy alive.

#### Scenario: Documentation covers the narinfo distinction

- **WHEN** an operator reads `docs/services/attic.md`
- **THEN** it explains the two-timestamp deletion condition and that a narinfo
  lookup is not an access
