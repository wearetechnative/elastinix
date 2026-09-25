---
# elastinix-dxps
title: roll the attic database change out to production
status: todo
type: task
priority: high
created_at: 2026-09-24T12:29:59Z
updated_at: 2026-09-24T12:43:29Z
parent: elastinix-mmic
blocked_by:
    - elastinix-dewz
---

Apply the same configuration to compute3-prod once non-production is proven.

Production could not be inspected while this was found (blocked by tooling), so first confirm
it shows the same symptom: `/var/lib/atticd/server.db` open and populated, PostgreSQL unused.

Acceptance: production atticd runs on PostgreSQL, a freshly minted token returns 200 for an
existing cache, and the cache public key recorded in the ledger still matches after a redeploy.
This unblocks `attic-shared-cache-and-substituters` task group 2, which creates the shared
`tn-infra` cache on the production endpoint and pins its key across the fleet.


## Measured 2026-09-24

Access granted; production confirms the inference, and adds a second defect.

- `checked-attic-server.toml` carries `database.url = "sqlite:///var/lib/atticd/server.db?mode=rwc"`,
  the same upstream default. The SQLite `cache` table is empty (0 caches, 0 objects, 0 NARs).
  No connection to `psql.tools.technative.cloud`. `/var/lib/private/atticd` sits on the root
  volume `/dev/nvme0n1p2`.
- The configured storage bucket is
  `compute3-persistant-storage-technative-workloads-prod-prod`, which **does not exist**. Only
  `…-workloads-prod` does. This is the doubled `-${infra_environment}` suffix that the
  archived change `atticd-solid-service` fixed in the repository; the deployed generation
  predates it, because the production compute3 deploy is blocked
  (technative-awsaccounts-workloads memory: prod compute3 apply fails on non-production
  references in the production Terraform state).

So production atticd is doubly inert: an empty local database, and a storage target that was
never created. Its real data — 2 caches, 1822 objects, 120 428 chunks — sits in PostgreSQL and
in the correctly named bucket, serving nobody.

Consequence for ordering: this bean now also depends on unblocking the production compute3
deploy. Shipping the database fix alone will not help production until a deploy can land there.
