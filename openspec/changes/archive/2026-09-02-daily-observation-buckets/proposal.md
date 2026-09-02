## Why

Observation accumulates forever into one document per host. The window a negative in-use claim rests on is therefore whatever has elapsed since the last reset — a deploy artefact rather than a period anyone chose. The report currently says "never observed in 804 samples", which sounds like broad coverage and is 68 hours.

ISO reporting here is monthly, so the evidence should be too. Bucketing observation per day makes the window the reporting period: "not observed during August, every day fully observed" is a claim an auditor can weigh, and 804 samples is not.

It also removes a class of defect rather than patching it. Ephemeral client ports accumulating as listeners, the coverage numerator and denominator covering different periods, and the epoch marker needed to repair a pair that had drifted all came from one forever-growing document whose fields fell out of step. All three were found only after deploying. A bucket sealed at the end of its day has nothing to drift against and no migration path where old and new state coexist.

## What Changes

- The in-use sampler writes a **daily bucket** per host instead of accumulating into one document. A bucket is sealed when the day rolls over and never modified again.
- Each bucket carries that day's in-use observations, that day's socket observations, the prevailing `haspHash`, and the `hasp-aws` values with their `changedKeys` — one daily series rather than four.
- A day is complete when **all uptime within that day was observed**, not when it contains 24 hours of observation. compute5-prod is stopped 8.5 hours every night; a 24-hour definition would mark it incomplete every day forever while its sampler works perfectly.
- The sampler reads `/proc/uptime` each run, so a gap can be attributed: uptime shorter than the gap means the host rebooted and the day stays complete; uptime longer means the host was running while the sampler was not, and the day says so.
- The scanner fetches every bucket it has not yet uploaded and writes each to `daily/<host>/<date>.json`. The existing conditional write skips one that already exists, so nothing tracks upload state.
- The accumulating window machinery is **removed**: `observedWindowSeconds`, `samplesInObservedWindow` and `observedWindowEpoch` exist only because observation never ended.
- The existing cumulative set is discarded rather than migrated. Two differently shaped sets of facts is worse than one gap.

Not in scope: the isotto tool that fetches a month of buckets from S3 and aggregates them, which is a separate change in that repository and depends on buckets existing there first. S3 lifecycle for the new prefix is a Terraform change outside both repositories.

## Capabilities

### New Capabilities

- `daily-observation-buckets`: the bucket's contents, when it is sealed, how a complete day is determined, and how a gap is attributed to downtime or to a stalled sampler.

### Modified Capabilities

- `hostinfo-socket-observation`: the cumulative set is replaced by daily buckets, and the window accounting is removed.
- `evidence-bundle`: sampling coverage is judged per day against uptime within that day, rather than against an accumulated window.
- `vulnerability-scan-central`: fetches the sealed buckets a host has not yet had uploaded.
- `evidence-s3-upload`: uploads each bucket under its own deterministic key alongside the per-run bundles.
- `vulnerability-prometheus-exporter`: coverage is derived from daily buckets, staying identical to the normalizer.

## Impact

- `modules/nixos/services/iso/service-hostinfo.nix` — the sampler writes and seals buckets; the window accounting comes out.
- `modules/nixos/services/iso/service-vulnerability-scan-central.nix` — fetch and upload the buckets.
- `modules/nixos/services/iso/evidence-normalizer.py` — coverage per day; the paired-window guard comes out.
- `modules/nixos/services/iso/service-vulnerability-prometheus-exporter.nix` — the same coverage change, so a dashboard and a report cannot disagree.
- **The cumulative in-use evidence is discarded on deploy.** Every host starts from an empty bucket series, so for one day no host can support a negative claim and every finding reports `inUse: "unknown"`. That is a deliberate gap, not a regression, and it must be recorded before the next monthly report.
- Deployment prerequisite outside this repository: an S3 lifecycle rule for the `daily/` prefix. The existing `s3:PutObject`-only policy already covers writing there.
- Roughly 20 kB per host per day, about 7 MB per host per year.

## Task

`.beans/elastinix-yx3a--replace-the-cumulative-in-use-document-with-daily.md`
