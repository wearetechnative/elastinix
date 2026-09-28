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
