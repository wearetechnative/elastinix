---
# elastinix-ulbs
title: 'atticd: configure garbage collection and a retention period'
status: in-progress
type: feature
priority: normal
created_at: 2026-09-25T13:41:30Z
updated_at: 2026-09-25T13:41:30Z
---

## Context

The atticd module renders `attic-server.toml` without a `[garbage-collection]`
section, so the server runs with attic's built-in defaults. The effect on
`attic.tools.technative.cloud` (verified 2026-09-25):

- the `tn-infra` cache row has `retention_period = NULL`, meaning "inherit the
  global setting"
- the global setting does not exist — there is no `[garbage-collection]` section
  in the generated config at all
- no garbage-collection entry appears in the atticd journal over 30 days
- the cache holds 704 NARs, 8737 chunks and 726 objects, and grows with every
  deploy of every compute, because the deploy wrapper pushes each system closure

Nothing is ever removed on age. The S3 bucket grows for as long as anyone pushes.
At today's scale that is cents, but it has no ceiling and nobody chose it: it is
the default leaking through, not a decision.

## What to build

Expose garbage collection in the elastinix atticd module, so a deployment can
state its retention instead of inheriting an absent default:

- a `garbage_collection` option group rendering `[garbage-collection]` into
  `attic-server.toml`, with at least `interval` and `default-retention-period`
- a sensible module default. Retention counts from **last access**, not from
  creation, so a closure that hosts still substitute is never collected. 90 days
  is a reasonable starting point: long enough that a rollback to a months-old
  generation still hits the cache, short enough that abandoned closures leave.
- leave per-cache retention alone; a cache row that wants its own period already
  overrides the global one through the API

## Acceptance

- `attic-server.toml` on compute3 contains a `[garbage-collection]` section
- the atticd journal shows the collector running on its interval
- the chunk count drops after a closure passes its retention, and a closure that
  is still being pulled does not

## Notes

Resolved by reading attic's `server/src/gc.rs` (2026-09-25). The collector's
behaviour is not what the absent config suggested:

- `interval` defaults to **43200 s (12 hours)**, not zero, so the collector *is*
  running in `--mode monolithic`. Only `interval = 0` disables it.
- `default-retention-period` defaults to **zero**, which disables **time-based**
  collection only. The comment in `config.rs` says so outright: "Zero (default)
  means time-based garbage-collection is disabled by default. You can enable it
  on a per-cache basis."
- `run_garbage_collection_once` then always runs `run_reap_orphan_nars` and
  `run_reap_orphan_chunks`, retention or not. Orphans are reaped every pass, and
  the chunk reaper deletes from the storage backend, not just the database.

So the bucket is not frozen: anything unreferenced already disappears within 12
hours. What is missing is purely the **age** dimension — a closure nobody pulls
any more is referenced forever by its object row, so it is never an orphan and
never leaves.

That also corrects an earlier note in this bean: the 64 MiB test closure was not
"already unheld and ignored by the collector". `run_reap_orphan_nars` requires
three things together — no object references the NAR, state Valid, and
`holders_count = 0`. Its `holders_count` is 0 and its state is Valid, but object
id 613 still points at it, so it is correctly not an orphan. `holders_count` is
an upload-time counter (`upload_path.rs` sets it to 1 while a NAR is being
uploaded), not a reference count of objects. Deleting the object row is all that
is needed; the next pass then removes the NAR and its chunks from S3.

This does not remove the need for retention, it sharpens it: retention is the
only mechanism that ever drops a path that is still indexed but no longer wanted.
Attic offers no per-path delete in its API or client either, so without retention
the only way to shrink the cache is direct database surgery.
