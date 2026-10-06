# attic-service Specification

## Purpose

Defines what the attic NixOS module configures: where the attic server takes
its database from, how the database credentials are kept out of the Nix store,
and what an operator must know about where cache state lives.

## Requirements

### Requirement: Take the database URL from the environment file by default

The module SHALL provide an option `elastinix.services.attic.database_url` of
type null-or-string, defaulting to `null`. When it is `null`, the attic server
configuration the module generates SHALL contain no `database.url` key, so that
the server takes its database URL from `ATTIC_SERVER_DATABASE_URL` in the
environment file. The upstream SQLite default SHALL NOT be applied implicitly.

#### Scenario: Default configuration omits database.url

- **WHEN** a host enables `elastinix.services.attic` without setting
  `database_url`
- **THEN** the generated `checked-attic-server.toml` contains no `url` key
  under `[database]`
- **AND** it contains no `sqlite://` URL

#### Scenario: Server uses the URL from the environment file

- **WHEN** the environment file sets `ATTIC_SERVER_DATABASE_URL` to a
  PostgreSQL URL and `database_url` is `null`
- **THEN** atticd connects to that PostgreSQL database and runs its migrations
  there
- **AND** atticd does not create or open `/var/lib/atticd/server.db`

#### Scenario: Missing URL fails loudly

- **WHEN** `database_url` is `null` and the environment file does not set
  `ATTIC_SERVER_DATABASE_URL`
- **THEN** atticd fails to start rather than falling back to SQLite

### Requirement: Render an explicit database URL

When `database_url` is a string, the module SHALL render it as
`database.url` in the generated attic server configuration, overriding the
upstream default.

#### Scenario: Explicit SQLite choice

- **WHEN** `database_url = "sqlite:///var/lib/atticd/server.db?mode=rwc"`
- **THEN** the generated `checked-attic-server.toml` carries exactly that
  `database.url`

### Requirement: Keep database credentials out of the Nix store

The module SHALL refuse, at evaluation time, a `database_url` that embeds a
password - either as `user:password@` in the authority or as a `password=`
query parameter - because the generated configuration is written to the
world-readable Nix store. The error SHALL direct the operator to
`ATTIC_SERVER_DATABASE_URL` in the agenix environment file.

#### Scenario: Password in the URL authority

- **WHEN** `database_url = "postgresql://attic:secret@db.example.com/attic"`
- **THEN** evaluation fails with an assertion naming
  `ATTIC_SERVER_DATABASE_URL`

#### Scenario: Password as query parameter

- **WHEN** `database_url = "postgresql://attic@db.example.com/attic?password=secret"`
- **THEN** evaluation fails with the same assertion

### Requirement: Cache identity survives loss of the instance's local state

With the database supplied through the environment file, a cache and its
signing keypair SHALL live only in that database. Losing atticd's local state
directory SHALL NOT change the set of caches the server reports or any cache's
public key. The module documentation SHALL state that the per-cache signing
keypair is stored in the database, so the database - not the S3 bucket -
determines whether a cache survives.

#### Scenario: State directory wiped and service restarted

- **WHEN** a cache is created, atticd is stopped, its local state directory is
  deleted, and atticd is started again
- **THEN** the cache is still reported by the server
- **AND** its public key is identical to the key reported before the wipe

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

### Requirement: The collector's work is visible in the journal

The module SHALL set a `RUST_LOG` directive for atticd by default, so that the
garbage collector's report of each pass reaches the journal. Without one, atticd
keeps only `error` and the collector -- which reports exclusively at `info` --
runs unobserved, which defeats the purpose of configuring it at all.

#### Scenario: Default configuration logs the collector

- **WHEN** a host enables `elastinix.services.attic` without setting `log_filter`
- **THEN** the atticd unit carries `RUST_LOG=attic_server=info` in its environment
- **AND** a pass writes `Found N caches subject to time-based garbage collection`
  and its deletion counts to the journal

#### Scenario: Silence can be chosen deliberately

- **WHEN** `log_filter = null`
- **THEN** the unit sets no `RUST_LOG`, which is atticd's own behaviour

### Requirement: Document what counts as access

The module documentation SHALL state that `last_accessed_at` is bumped only when
a client downloads the NAR, and not when it fetches the `.narinfo`. A host that
already holds a path fetches only the narinfo, so continued use by hosts that
are already up to date does not keep a cached copy alive.

#### Scenario: Documentation covers the narinfo distinction

- **WHEN** an operator reads `docs/services/attic.md`
- **THEN** it explains the two-timestamp deletion condition and that a narinfo
  lookup is not an access
