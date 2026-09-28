---
# elastinix-mmic
title: atticd cache state must survive instance replacement
status: in-progress
type: epic
priority: high
created_at: 2026-09-24T12:29:32Z
updated_at: 2026-09-24T12:37:13Z
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
