---
# elastinix-eyrj
title: decide the fate of the orphaned caches in the attic database
status: in-progress
type: task
priority: normal
created_at: 2026-09-24T12:29:59Z
updated_at: 2026-09-24T13:23:51Z
parent: elastinix-mmic
blocked_by:
    - elastinix-dewz
---

The PostgreSQL `attic` database holds `main` (public) and `technative` (private), both created
2025-04-22 and never soft-deleted, which the running server has not served since it fell back
to SQLite. Once atticd points at PostgreSQL again these caches reappear — including whatever
store paths their chunk index still references in S3.

Decide and execute: adopt them, or delete them and their S3 objects. Either way the outcome
must match `stack/ec2_compute3/attic-tokens.md`, which the workloads change
`attic-shared-cache-and-substituters` (task 1.5) rewrites to record legacy caches as dormant.

Acceptance: the set of caches the server reports equals the set the ledger documents, with no
S3 objects belonging to caches that no longer exist.


## Measured 2026-09-24 (non-production)

The orphaned data is not trivial:

| | |
|--------------------------|--------|
| caches                   | 2 (`main` public, `technative` private) |
| objects (store paths)    | 480    |
| NARs                     | 479    |
| chunks                   | 40 247 |

The S3 bucket `compute3-persistant-storage-technative-workloads-nonprod` holds the matching
`<uuid>.chunk` objects at the bucket root — **flat keys with no cache or prefix component**.

That gives a hard ordering constraint: the PostgreSQL chunk index is the only thing that maps
an S3 object to a cache. Delete or reset the database first and the ~40k objects become
unattributable garbage that no GC can ever identify, in the same bucket the new shared cache
is meant to use.

So, before anything is created in that bucket, either

1. delete the caches through attic itself, so its garbage collection removes the chunks, or
2. empty the bucket wholesale while the database still matches it.

Recommendation: option 2 for non-production (roughly 2.5 GB at the configured 64 KiB average
chunk size, of packages built in April 2025 that nothing pulls today), and record both caches
as dormant in `stack/ec2_compute3/attic-tokens.md`. Whatever is chosen, do it before
`attic-shared-cache-and-substituters` task 2.1 creates `tn-infra`.


## Decision 2026-09-24: discard

Owner decision: throw the legacy cache data away. Non-production is being purged now.

Two corrections to the measurement above, found while auditing the bucket before deleting:

- The bucket holds **275 574** `.chunk` objects totalling **6.47 GiB**, not the ~40k implied by
  the PostgreSQL index. Roughly 235k chunks were already unreferenced garbage before today,
  which is its own argument: nothing has been garbage-collecting this bucket.
- The bucket is **not exclusively attic's**. It also holds `wouter.txt` and an empty `zammad/`
  key. So the purge deletes `*.chunk` only; emptying the bucket wholesale would take other
  people's objects with it.

### Production is worse, and is a separate decision

Measured on compute3-prod (i-0532dc56800ee5583) once access was granted:

| | |
|---------------------------|-----------------------------------------------|
| caches in PostgreSQL      | `wouterscache`, `technativecache` (2025-08-07) |
| objects / NARs / chunks   | 1822 / 1662 / 120 428                          |
| S3 bucket with the data   | `compute3-persistant-storage-technative-workloads-prod`, chunks written up to 2025-09-03 |
| bucket the service is configured with | `compute3-persistant-storage-technative-workloads-prod-prod` — **does not exist** |
| SQLite `cache` table      | empty |

So production atticd currently writes nowhere: it runs on an empty SQLite database and points
at a bucket that was never created (the doubled `-${infra_environment}` suffix the archived
change `atticd-solid-service` fixed in the repo but which has never been deployed to
production). Its real data sits in PostgreSQL plus the correctly named bucket, unreachable.

Production purge is not covered by the non-production decision and has not been executed.


## Executed 2026-09-24

Both environments, owner-approved (discard, and rebuild the database rather than truncate it).

1. `pg_dump` taken first and left on each host as insurance: `/root/attic-predrop-2026-09-24.sql.gz`
   (6.9 MB non-production, 24 MB production). Delete once the rebuild is proven.
2. `DROP DATABASE attic` + `CREATE DATABASE attic`. Both databases now report collation version
   **2.42**, so the mismatch that beans `technative-awsaccounts-workloads-er3c` / `-9zde` /
   `-54pl` describe is gone for `attic` — it was solved by discarding, not by reindexing.
3. `*.chunk` objects deleted from both buckets; `wouter.txt` and `zammad/` left alone in
   non-production.

### Encountered: `template1` on the production instance is itself stale

`CREATE DATABASE attic` failed on production with

```
ERROR: template database "template1" has a collation version mismatch
DETAIL: The template database was created using collation version 2.38, but the operating
        system provides version 2.42.
```

Worked around with `CREATE DATABASE attic TEMPLATE template0` (template0 carries no recorded
collation version, so it is exempt from the check). The underlying problem is wider than
attic — on `psql.tools.technative.cloud` these databases are still at 2.38:

`atuin`, `default`, `freshrss`, `hedgedoc`, `hydra`, `pontifex`, `solidtime`, `test`, `umami`,
and `template1` itself. Only `documenso`, `postgres`, `vaultwarden` and `zammad` are at 2.42.

Until `template1` is refreshed, **every** new database on that instance must be created with
`TEMPLATE template0` or it fails. That belongs in the workloads collation beans, not here.


**Correction, same day:** `template1` has since been refreshed on both instances — both now
report collation version 2.42, and a plain `CREATE DATABASE` (no `TEMPLATE template0`) succeeds
on production again. Nine databases there are still at 2.38: `atuin`, `default`, `freshrss`,
`hedgedoc`, `hydra`, `pontifex`, `solidtime`, `test`, `umami`.

**Bucket ownership checked:** the buckets are the generic compute3 `persistent_storage` module,
not attic-only, so they were audited before deleting. Non-production held 275 574 `.chunk`
objects plus `wouter.txt` and an empty `zammad/` marker; production holds `.chunk` objects only
(zero non-chunk keys). `elastinix.services.zammad` declares no S3 storage at all, so no zammad
data lives in either bucket. The delete filter matched `*.chunk` exclusively.


**Purge complete 2026-09-24.** Non-production: 275 574 chunks deleted, `wouter.txt` and
`zammad/` left in place. Production: 120 428 chunks deleted, bucket now empty (0 objects). Both
runs exited 0 with no errors. Remaining work on this bean is the ledger side —
`stack/ec2_compute3/attic-tokens.md` must record both environments' caches as gone
(`attic-shared-cache-and-substituters` task 1.5).
