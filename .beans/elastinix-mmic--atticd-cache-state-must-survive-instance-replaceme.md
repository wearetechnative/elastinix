---
# elastinix-mmic
title: atticd cache state must survive instance replacement
status: completed
type: epic
priority: high
created_at: 2026-09-24T12:29:32Z
updated_at: 2026-09-28T16:17:26Z
---

`elastinix.services.attic` (modules/nixos/services/service-attic.nix) sets `listen`,
`api-endpoint`, `chunking` and `storage`, but never `database.url`. The generated
`checked-attic-server.toml` therefore falls back to the upstream NixOS default
`sqlite:///var/lib/atticd/server.db?mode=rwc`, and the `ATTIC_SERVER_DATABASE_URL` supplied
through the agenix EnvironmentFile cannot override it: in attic that variable is a serde
*default* for `database.url`, consulted only when the TOML omits the key (see elastinix-1itf).

Measured on compute3-nonprod (2026-09-24): the running atticd holds
`ATTIC_SERVER_DATABASE_URL` in its process environment, yet `/var/lib/private/atticd/server.db` (on the
root volume, systemd `DynamicUser` + `StateDirectory`) is the open database, there is no
connection to port 5432, and its `cache` table is empty, while
the PostgreSQL `attic` database still holds the caches `main` and `technative` created
2025-04-22. Any valid token consequently gets `{"code":404,"error":"NoSuchCache"}` for every
cache name.

Why this matters: the per-cache signing keypair lives in that database. The NARs live in S3.
Replacing the instance therefore loses the keypair and the chunk index while keeping the S3
objects — an unreadable cache, and a `trusted-public-keys` entry on every consumer that can
never be satisfied again.

This blocks technative-awsaccounts-workloads change `attic-shared-cache-and-substituters`,
whose design pins one shared cache's public key across the whole fleet.

## Outcome (2026-09-28)

Resolved. The module renders no `database.url` when `database_url` is null
(`lib.mkForce { }` discards the upstream mkDefault SQLite URL), so attic reads
`ATTIC_SERVER_DATABASE_URL` from the environment file. Merged as part of PR #40,
commit `4ee0777`, with an assertion refusing a URL that carries a password --
the generated configuration lands in the world-readable Nix store.

Verified in both environments: `[database]` is empty in the generated
configuration, no `server.db` is open by the atticd process, and attic's tables
live in PostgreSQL. A NixOS VM test creates a cache, wipes atticd's state
directory, restarts and compares the public key, so the property this epic is
named after is now checked rather than assumed.

The shared `tn-infra` cache has run on that database since 2026-09-25 and serves
all twelve compute hosts.
