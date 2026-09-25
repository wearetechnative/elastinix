---
# elastinix-dewz
title: point compute3 non-production atticd at PostgreSQL and verify
status: todo
type: task
priority: high
created_at: 2026-09-24T12:29:47Z
updated_at: 2026-09-24T13:12:32Z
parent: elastinix-mmic
blocked_by:
    - elastinix-1itf
---

Deploy the new option on compute3-nonprod (stack/ec2_compute3 in
technative-awsaccounts-workloads) against the existing `attic` database on
psql.np-tools.technative.cloud.

Acceptance:
- `atticd` starts, runs its migrations against PostgreSQL, and `/var/lib/atticd/server.db` is
  no longer opened.
- A freshly minted token returns 200 (not 404 `NoSuchCache`) for a cache that exists.
- Restarting the instance (or a full redeploy) leaves the cache and its public key intact.

Note: the `attic` database carries a collation-version mismatch (created with 2.40, OS
provides 2.42). See technative-awsaccounts-workloads-er3c / -9zde; resolve that before
putting real load on it.


## Notes 2026-09-24

Baseline measured on compute3-nonprod before the change:

- `atticd` holds `/var/lib/private/atticd/server.db` open (systemd `DynamicUser` +
  `StateDirectory`), on the root volume `/dev/nvme0n1p2` — the volume that is replaced when the
  instance is redeployed. There is no data volume for it; only `/vaultwarden` has one.
- The process has no TCP connection to `psql.np-tools.technative.cloud`.
- That SQLite `cache` table is empty, so every valid token gets `404 NoSuchCache`.

Verification recipe for after the fix (the endpoint `/_api/v1/cache-config/<name>` returns 401
when the token is rejected and 404/200 once its signature is accepted, so use a cache that
exists to tell 404-because-empty-database apart from 404-because-no-such-cache):

```bash
PID=$(systemctl show atticd -p MainPID --value)
ls -l /proc/$PID/fd | grep -E 'server\.db'   # must be empty afterwards
ss -tnp | grep "pid=$PID"                    # must show a connection to 5432
```


### Open risk, not yet answered

The PostgreSQL `attic` schema was last migrated by the attic version running in April 2025;
the binary in use now is `attic-0-unstable-2025-09-24`. Pointing it at that database makes it
run the intervening migrations against live data on first start. Take a dump of the `attic`
database first (`pg_dump`), and treat a failed or partial migration as a rollback, not as
something to repair in place.


**Risk retired 2026-09-24:** both `attic` databases were dropped and recreated empty
(elastinix-eyrj), so there is no longer any live data to migrate over. Attic will build its
schema from scratch on first connect. The collation note above is likewise obsolete for
`attic`; the fresh databases are at version 2.42.
