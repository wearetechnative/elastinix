---
# elastinix-oiat
title: 'compute2: point the badgersbay blackbox probe at /health'
status: in-progress
type: task
priority: normal
tags:
    - badgersbay
    - monitoring
created_at: 2026-09-18T08:59:42Z
updated_at: 2026-09-18T14:19:34Z
---

The other half of elastinix-wckg. Elastinix now declares health checks against
`/health` and documents what a probe must target; the probe itself is not in
that repository.

## Where it is

The thirty-second poll is the monitoring stack, not anything badgersbay
declares:

- `globalConfig.scrape_interval = "30s"` in the monitoring flake's
  `module/prometheus/prometheus.nix` - that is the cadence, not a per-probe
  setting
- the blackbox exporter's `http_2xx` module, `method: GET`
- `job_name = "blackbox-<customer>"`, reading its targets from
  `/etc/prometheus/customers/<customer>/probes/urls.yaml` via `file_sd_configs`

That file is `elastinix.services.grafana-prometheus.customers.*.probesFile` - a
path into the host configuration repository. A bare `https://badgersbay.<domain>`
entry requests `/`, which is the dashboard, behind basic auth, answering 401 to
an unauthenticated probe whether the service is healthy or not. The source
address is `127.0.0.1` because the probe reaches the server through nginx.

## To fix

Change the entry in compute2's probes file:

    https://badgersbay.<domain>    ->    https://badgersbay.<domain>/health

Then confirm the 401 lines stop and `probe_success` for that instance goes to 1.

## Worth knowing

A 200 from `/health` does not mean the storage location is there - the server
answers 200 with `storage.accessible` false. Asserting that from prometheus
needs a blackbox module with `fail_if_body_not_matches_regexp`, which lives in
the monitoring flake. Elastinix covers it from the other side, in
`healthchecks.localCommands.badgersbay-storage`.

## Origin

Split out of elastinix-wckg, which is closed by
openspec/changes/archive/2026-09-18-badgersbay-health-checks.
