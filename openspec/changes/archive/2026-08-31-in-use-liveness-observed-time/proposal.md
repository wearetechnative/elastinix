## Why

The in-use liveness guard rejects a host's evidence when its sample count falls too far below what the observation window implies. It computes that expectation from **elapsed wall-clock time**, which assumes the host never stops.

compute5-prod carries `InstanceScheduler = "6:30am-to-10pm-everyday"` and is stopped 8.5 hours a night. Its 343 samples over a 70.3-hour window imply 845, so it reads as 40.6% coverage and fails the 50% threshold. Measured against the ~44.8 hours it was actually running, the same samples are ~64% and pass comfortably. The sampler is healthy: between two bundles today it produced 59 samples where 62 were due.

The consequence is that all 137 of compute5-prod's critical and high findings report `inuse="unknown"`, 47% of the fleet total, and none of them can be assessed either way. The guard also fails in the other direction: a host that runs continuously but whose sampler died can still pass, because elapsed time and observed time are indistinguishable to it.

## What Changes

- The sampler accumulates the time it actually observed, adding the gap since its previous sample when that gap is within a small multiple of the interval, and a single interval otherwise.
- The liveness guard compares the sample count against that accumulated time instead of the elapsed calendar window. A host stopped on a schedule is no longer mistaken for a host whose sampler has died.
- The Prometheus exporter takes the identical change, so a dashboard's `inuse` label continues to mean what a bundle's `inUse` value means.
- A document written before the field existed falls back to the elapsed window rather than being rejected outright.

Not in scope: bounding a negative in-use claim by how often the host's own work runs. That was scoped into this change and removed — deriving a cadence from timer configuration turned out to measure the wrong thing, because every "monthly" and "quarterly" unit on the fleet fires daily and decides internally whether to act. It is now `elastinix-sw3u`, back in exploration.

## Capabilities

### Modified Capabilities

- `evidence-bundle`: the in-use liveness check measures sampling coverage against observed time rather than elapsed time.
- `hostinfo-socket-observation`: the sampler records how much time it observed.
- `vulnerability-prometheus-exporter`: the coverage check behind the `inuse` label uses observed time.

## Impact

- `modules/nixos/services/service-hostinfo.nix` — sampler accumulates an observed window.
- `modules/nixos/services/evidence-normalizer.py` — guard denominator changes.
- `modules/nixos/services/service-vulnerability-prometheus-exporter.nix` — same guard change.
- compute5-prod's 137 undetermined findings become assessable, so not-affected and open counts rise and undetermined falls. That is a measurement change, not remediation, and belongs in `elastinix-e79k`.
- No change to `hasp.json`, so profile hashes are unaffected.

## Task

`.beans/elastinix-slry--in-use-liveness-guard-measures-elapsed-time-so-hos.md`
