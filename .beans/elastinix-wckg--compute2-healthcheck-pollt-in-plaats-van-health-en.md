---
# elastinix-wckg
title: 'compute2: healthcheck polls / instead of /health and measures nothing'
status: todo
type: bug
priority: normal
tags:
    - badgersbay
    - monitoring
created_at: 2026-09-15T20:31:30Z
updated_at: 2026-09-15T20:31:30Z
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
