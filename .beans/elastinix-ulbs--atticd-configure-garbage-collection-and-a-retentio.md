---
# elastinix-ulbs
title: 'atticd: configure garbage collection and a retention period'
status: todo
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

Confirm before shipping whether attic's collector removes **orphaned chunks**
when retention is disabled, or only as part of expiring NARs. That determines
whether deleting a store path from the cache today frees its S3 objects at all,
which is the other half of this problem.

Evidence from 2026-09-25: a 64 MiB test closure pushed that day sits in the cache
as nar id 591 with **`holders_count = 0`** and 1024 chunks. It is already
unheld — nothing references it — and it was not collected. So the blockage is not
reference counting; the collector simply does no work while retention is absent.
Deleting rows by hand therefore buys nothing: the path is already in the state
the collector is supposed to act on. Configuring retention is the only thing that
reclaims anything.

Attic offers no per-path delete either. `attic cache` has create, configure,
destroy and info, and nothing else. Retention is the only granular lever there
is, which makes this bean the sole route to ever shrinking the bucket.
