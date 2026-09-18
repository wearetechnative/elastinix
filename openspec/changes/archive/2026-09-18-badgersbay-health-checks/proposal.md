## Why

Something on compute2-prod asks badgersbay `GET /` every thirty seconds without
credentials and is told 401 every time:

```
20:25:22  127.0.0.1 - "GET / HTTP/1.1" 401
20:25:52  127.0.0.1 - "GET / HTTP/1.1" 401
20:26:22  127.0.0.1 - "GET / HTTP/1.1" 401
```

`/` is the dashboard, and the dashboard sits behind basic auth. An unauthenticated
request to it answers 401 whether the server is healthy, whether the storage
location is gone, and whether the compliance cache is empty. The check cannot
distinguish those states from each other, and it writes two log lines a minute
while failing to.

The poller is the monitoring stack, not anything badgersbay declares. Prometheus
scrapes at `globalConfig.scrape_interval = "30s"`, the blackbox exporter's
`http_2xx` module probes whatever URLs the customer's `probesFile` lists, and a
bare `https://badgersbay.<domain>` entry probes `/`. Nothing in this repository
sets that file; it lives in the host configuration.

What this repository can fix is the other half: the badgersbay module declares no
health check at all, so there is nothing for a host or an operator to point at
except the dashboard.

## What Changes

- **The module declares its own health checks**, through `nixos-healthchecks` -
  the framework `lib/os_config_live.nix` and `lib/os_config_vm.nix` already
  import on every host, and which `elastinix.programs.e2e-twenty` already uses:
  - `healthchecks.http.badgersbay` requests `http://127.0.0.1:<port>/health`,
    expects 200, and expects the body to name `honeybadger-server`.
  - `healthchecks.localCommands.badgersbay-storage` reads the same response and
    fails unless `storage.accessible` is true, because the server answers 200
    with `"accessible": false` when the directory it writes submissions to has
    gone. A status code alone would call that healthy.
- **The documentation stops suggesting a health check and describes the one the
  module declares.** `docs/services/badgersbay.md` currently offers a
  `badgersbay-health` timer as an example to copy; it is replaced by what is now
  configured, by how to run it, and by what a monitoring probe must target -
  `/health`, never `/`, with the reason.

## Capabilities

### New Capabilities

None. Health checking is behaviour of the badgersbay service module and belongs
with the rest of it.

### Modified Capabilities

- `badgersbay-service`: gains a requirement that the module declares a health
  check against the unauthenticated `/health` endpoint and that the check reads
  the response body rather than only its status code, so that a probe against
  the authenticated dashboard is not the thing a host is left to invent

## Impact

- `modules/nixos/services/service-badgersbay.nix`: two definitions added under
  `config`; no option added, no option changed, and the unit is untouched.
- `docs/services/badgersbay.md`: the "Monitoring / Health Checks" section is
  rewritten, and the health endpoint section gains the probe guidance.
- No host configuration in this repository changes, because none configures a
  probe. Every elastinix host already imports the healthchecks module, so the
  new definitions land without a host doing anything.
- **Not fixed here**: the 401s themselves. The probe target is an entry in
  compute2's `probesFile`, which is in the host configuration repository. This
  change gives that entry something correct to point at and records what it must
  be; changing it is tracked separately.

## Tracking

- Bean: [elastinix-wckg](../../../.beans/elastinix-wckg--compute2-healthcheck-pollt-in-plaats-van-health-en.md)
