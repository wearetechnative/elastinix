---
# elastinix-wckg
title: 'compute2: healthcheck polls / instead of /health and measures nothing'
status: completed
type: bug
priority: normal
tags:
    - badgersbay
    - monitoring
created_at: 2026-09-15T20:31:30Z
updated_at: 2026-09-18T08:59:56Z
openspec-link: openspec/changes/archive/2026-09-18-badgersbay-health-checks
---

Something on compute2-prod polls the badgersbay dashboard at `/` every 30
seconds, without credentials:

    20:25:22  127.0.0.1 - "GET / HTTP/1.1" 401
    20:25:52  127.0.0.1 - "GET / HTTP/1.1" 401
    20:26:22  127.0.0.1 - "GET / HTTP/1.1" 401

## Why this is wrong

`/` is the dashboard and sits behind basic auth. The poller has no credentials,
so it always gets a 401 - whether or not the service is healthy. A 401 also
comes back when storage is unreachable or the compliance cache is empty. The
check measures nothing and fills the log while doing it.

`/health` is the endpoint that exists for this: no authentication, and it
answers with status, uptime, storage accessibility and report statistics. Since
badgersbay b4ae8ab those figures are also correct on a compliance install.

## To establish

The source has not been found yet:

- `badgersbay.timer` is `OnCalendar=hourly`, so that is not it
- no healthcheck unit found in `systemctl list-units`
- `service-badgersbay.nix` holds no healthcheck configuration
- compute2's `hostconf.nix` mentions `healthchecks` nowhere

Candidates: `nixos-healthchecks` (an elastinix input), a blackbox exporter, or
something in the monitoring stack. The request comes from 127.0.0.1, so it runs
on the host itself.

## To fix

1. Find the poller
2. Point it at `http://localhost:9117/health`, expecting 200
3. Consider checking content rather than just the status code:
   `storage.accessible` is the meaningful indicator, because the server also
   answers 200 when the storage location has gone


## Summary of Changes

**The poller was the monitoring stack**, not anything badgersbay declares -
which is why nothing turned up in `systemctl list-units`. Prometheus scrapes at
`globalConfig.scrape_interval = "30s"`, the blackbox exporter's `http_2xx`
module probes whatever the customer's `probesFile` lists, and a bare
`https://badgersbay.<domain>` entry probes `/`. The source address is
`127.0.0.1` because the probe arrives through nginx.

That file is in the host configuration repository, so pointing it at `/health`
is tracked separately as elastinix-oiat.

**What changed here** is the half the module owns: it declared no health check
at all, so the dashboard was the only thing a host had to point at. It now
declares two, through `nixos-healthchecks`:

- `healthchecks.http.badgersbay` - `http://127.0.0.1:<port>/health`, 200, with
  `honeybadger-server` in the body.
- `healthchecks.localCommands.badgersbay-storage` - parses the same response and
  fails unless `storage.accessible` is true.

The second exists because the first cannot cover it: the server answers 200 with
`storage.accessible` false when the directory it writes submissions to has gone,
so a status code alone would call that healthy. It is a script rather than
`expectedContent` on the HTTP check - that option is interpolated into generated
Python unescaped, and `"accessible": true` carries the quotes `json.dumps`
writes, which makes the generated check `E999 SyntaxError` at build time.

No unit was added and none changed: `badgersbay.service` builds to the same
store path as before. No timer either - answering a complaint about a useless
poller by adding a second poller to every host was the one thing not to do.

`docs/services/badgersbay.md` no longer suggests writing a `badgersbay-health`
timer; it documents the checks, how to run them, and that a probe targets
`/health` and never `/`.

- OpenSpec: openspec/changes/archive/2026-09-18-badgersbay-health-checks
- Follow-up: elastinix-oiat (the probes file on compute2)
