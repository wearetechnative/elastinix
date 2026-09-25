## Why

The attic module renders no `[garbage-collection]` section, so atticd runs on
its built-in defaults. Reading `server/src/gc.rs` shows what those actually do,
which is not what the missing section suggests:

- `interval` defaults to 12 hours, so the collector **is** running
- `run_reap_orphan_nars` and `run_reap_orphan_chunks` run on every pass,
  regardless of retention, and the chunk reaper deletes from the storage backend
  as well as the database
- `default-retention-period` defaults to **zero**, which disables only the
  **time-based** arm

So unreferenced data already disappears within twelve hours. What is missing is
the age dimension. An object row keeps its NAR referenced forever, so a closure
nobody pulls any more is never an orphan and never leaves. Measured on
`attic.tools.technative.cloud` on 2026-09-25: 704 NARs, 8737 chunks, 726
objects, every one of them still indexed, and the deploy wrapper adds a system
closure on every deploy of every compute.

Attic offers no per-path delete — its API and client expose create, configure,
destroy and info, nothing finer. Without retention the only way to drop a path
that is still indexed is direct database surgery on a production cache. That is
not a workflow anyone should need.

## What Changes

- A `garbage_collection` option group on `elastinix.services.attic` that renders
  a `[garbage-collection]` section into the attic server configuration.
- `interval`, defaulting to the upstream 12 hours, so the rendered value states
  what was previously only implied.
- `default_retention_period`, defaulting to **90 days**, changing the module's
  effective behaviour from "nothing ever expires" to "a closure that is both
  older than 90 days and untouched for 90 days is dropped".
- Documentation of what "untouched" means, because it is easy to get wrong: the
  deletion requires `created_at < cutoff` **and** `last_accessed_at` null or
  older than the cutoff, and only a NAR download bumps `last_accessed_at` — a
  `.narinfo` lookup does not.

## Capabilities

### New Capabilities

_None._

### Modified Capabilities

- `attic-service`: adds requirements for rendering the garbage-collection
  section and for the retention default. The capability previously said nothing
  about garbage collection at all.

## Impact

- `modules/nixos/services/service-attic.nix`
- `docs/services/attic.md`
- `tests/` — a new evaluation test asserting the rendered section
- Deployments: compute3 in both environments starts expiring cache objects 90
  days after their last download. Nothing else changes; a host that no longer
  finds a path in the cache falls back to building or to `cache.nixos.org`.
