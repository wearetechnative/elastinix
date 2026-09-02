---
# elastinix-slry
title: In-use liveness guard measures elapsed time, so hosts on a stop/start schedule can never pass
status: completed
type: bug
priority: high
created_at: 2026-08-28T12:18:53Z
updated_at: 2026-08-31T09:52:47Z
parent: elastinix-p9gu
openspec-link: openspec/changes/archive/2026-08-31-in-use-liveness-observed-time
---

All 137 critical and high findings on compute5-prod report as undetermined, so none of them can be justified or deprioritised. The cause is the liveness guard, not the host.

## Measurement (2026-08-28 run)

  window            70.3 h   (Tue 13:46 -> Fri 12:04 UTC)
  expected samples  845      (window / 300s interval)
  actual samples    343
  ratio             40.6%    guard rejects below 50%
  missing           502 samples = 41.8 h unobserved

## Root cause

compute5-prod carries the tag InstanceScheduler = "6:30am-to-10pm-everyday" and its
LaunchTime is 2026-08-28T04:30:51Z. It is stopped 8.5 h per day. Across the three
nights in that window that is 25.5 h of the 41.8 h missing; the remainder is
redeploys and reboots earlier in the window.

The sampler is healthy. Between the 06:54 and 12:04 bundles the count went
284 -> 343, which is 59 samples where 62 were due: 95%. It runs correctly whenever
the host is up.

## Why this is a design flaw

The guard derives expected samples from the WALL-CLOCK window between firstSample
and lastSample, which assumes continuous uptime. Any host on a stop/start schedule
therefore fails permanently no matter how healthy its sampler is. compute5-prod
will report undetermined forever.

The same heuristic is mirrored in the Prometheus exporter, so inuse="unknown" is
showing on dashboards for the same wrong reason. Both consumers must be changed
together or the bundle and the dashboards will disagree.

## Proposed fix

Measure against observed time rather than elapsed time. The sampler accumulates a
windowSecondsObserved field: on each sample add the delta since the previous
sample when it falls within a few intervals, otherwise add a single interval
because the host was off. Consumers then compute
expected = windowSecondsObserved / intervalSeconds, and scheduled downtime stops
counting as a sampling gap.

compute5-prod has 343 samples over roughly 44.8 h of real uptime, about 64%, which
passes comfortably.

## Expected effect

Converts 137 undetermined findings (47% of the fleet critical and high total) into
roughly half auto-justified as not-in-use and half open for a decision. This is
the last collection gap in the pipeline.

## Affected

- modules/nixos/services/service-hostinfo.nix (sampler: record observed window)
- modules/nixos/services/evidence-normalizer.py (load_inuse gap check)
- modules/nixos/services/service-vulnerability-prometheus-exporter.nix (load_inuse gap check)
- spec delta for hostinfo-service or hostinfo-socket-observation, plus the exporter spec

## Follow-up: elastinix-yx3a

The observed-window accounting introduced here — `observedWindowSeconds`,
`samplesInObservedWindow` and the `observedWindowEpoch` marker that repairs a
drifted pair — exists because observation accumulates forever into one document.
With daily buckets a sealed day has nothing to drift against, so that machinery is
replaced rather than maintained. The lesson it taught survives: coverage is measured
against observed time, not elapsed time, and that is the one open design question in
elastinix-yx3a.
