## Context

Everything below follows from reading attic's `server/src/gc.rs` and
`server/src/config.rs` at the revision packaged in nixpkgs
(`attic-0-unstable-2025-09-24`), verified against the live database on
`attic.tools.technative.cloud` on 2026-09-25.

`run_garbage_collection_once` does three things in order:

1. `run_time_based_garbage_collection` — deletes **objects** whose cache has a
   non-zero retention period
2. `run_reap_orphan_nars` — deletes NARs that no object references, that are in
   state `Valid`, and whose `holders_count` is 0
3. `run_reap_orphan_chunks` — deletes chunks that no chunkref references, from
   the storage backend as well as the database

Steps 2 and 3 are unconditional. Step 1 selects caches with
`COALESCE(cache.retention_period, <global default>) != 0`, so with the global
default at zero and every cache row NULL, it finds nothing and the other two
steps have nothing to find either: every NAR is still referenced by its object.

## Goals / Non-Goals

**Goals**

- Make the collector's behaviour visible in the generated configuration instead
  of inherited invisibly.
- Give the cache an upper bound in time, so the bucket stops being append-only.

**Non-Goals**

- Per-cache retention. Attic already supports it through
  `attic cache configure <name> --retention-period`, and a cache row that sets
  its own value overrides the global one. The module has no business duplicating
  that.
- Deleting individual store paths. Attic offers no such operation and this change
  does not invent one.

## Decisions

### D1 — Render the section unconditionally, including the interval

The alternative was to render `[garbage-collection]` only when an operator sets
something. That keeps the diff smaller but preserves the exact problem this
change exists to fix: the collector's behaviour stays invisible, and the next
person to look at `checked-attic-server.toml` has to read attic's source to
learn that a collector runs at all. The interval is therefore rendered at its
upstream value of 12 hours — not a change in behaviour, a change in visibility.

### D2 — Default retention of 90 days, not zero

Zero preserves today's behaviour and would make the option a knob nobody turns.
The defaults that matter are the ones that apply when nobody thinks about them.

90 days was chosen against two failure modes. Too short, and a compute that is
deployed rarely finds its closure gone and falls back to a full transfer over
the operator's connection — measured at roughly eight times slower than the
cache. Too long, and the bound is theoretical. A quarter covers the realistic
rollback window: a generation from a few months ago is still substitutable.

### D3 — `null` means zero, not "omit the key"

An operator who wants attic's original behaviour needs a way to say so, and it
should read as intent rather than as absence. `null` renders
`default-retention-period = "0"`, which is attic's own encoding for "time-based
collection off". The key stays present, so the configuration continues to state
what happens.

### D4 — Keep the deletion condition in the documentation, not just the option

The condition is a conjunction that is easy to misread:

```sql
created_at < cutoff
AND (last_accessed_at IS NULL OR last_accessed_at < cutoff)
```

"90 days" therefore means old **and** unused, never just old. And
`bump_object_last_accessed` is called from the NAR download handler only, not
from the narinfo handler, so a host that already holds a path does not keep the
cached copy alive by checking for it. Both facts belong where an operator will
look, which is the service documentation.

## Risks / Trade-offs

- **A rarely-deployed host loses its cache hit.** It falls back to a transfer
  over the operator's connection, which is slower but correct. The 90-day window
  makes this unlikely rather than impossible.
- **The first collection after this lands may delete a lot at once.** The cache
  was created on 2026-09-25, so nothing can be 90 days old before late December
  2026; there is no cliff to schedule around on this deployment.
- **Deleting objects does not immediately free S3.** Chunks go on the following
  pass, up to 12 hours later, and the reaper processes at most 65535 chunks per
  pass on PostgreSQL.

## Migration Plan

No migration. The option's default takes effect on the next deploy of a host
running atticd; existing caches keep any retention period they set for
themselves.

## Open Questions

None. The behavioural questions this change started from were answered from the
source and are recorded in Context.
