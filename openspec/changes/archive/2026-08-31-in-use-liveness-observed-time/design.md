## Context

See proposal.md — Why.

Constraints:

- `runtime-facts.json` accumulates for the life of a host, so a new field must appear without discarding history, and the guard must tolerate its absence for the first window's worth of samples.
- The exporter and the normalizer already duplicate four rules — severity thresholds, output grouping, vendor exclusion and this guard — kept in step by convention and a spec requirement rather than by shared code. This change modifies the fourth of them in both places.
- The sampler cannot see across a reboot. It only knows the timestamp of its own previous sample.

## Goals / Non-Goals

**Goals:**

- A host stopped on a schedule is distinguishable from a host whose sampler has died.
- compute5-prod's evidence becomes usable without weakening the guard for anything else.

**Non-Goals:**

- Bounding a negative claim by how often the host's work actually runs. That is `elastinix-sw3u`.
- Extracting the four duplicated rules into a shared module. Worth doing, and not mixed into a correctness fix.

## Decisions

### Accumulate in the sampler rather than infer downstream

The sampler adds the gap since its previous sample when that gap is within a multiple of the interval, and one interval otherwise. Consumers read the total.

*Alternative considered:* read cumulative uptime from the kernel. Simpler, but it counts time before the sampler was enabled and time when the sampler was stopped while the host ran, which is exactly the failure the guard exists to catch.

*Alternative considered:* have consumers infer downtime from gaps in the document. The document does not retain per-sample timestamps, only first and last, so the information is not there to infer from.

### Three intervals separates a slow sample from downtime

Too small and a delayed sample is credited as downtime, inflating coverage. Too large and a real outage is credited as observed time, deflating it. Three is the starting point and belongs in an option so a host with a different cadence can tune it.

This threshold is the one judgement call in the change, and it errs toward the safe direction: crediting only one interval across a genuine gap understates observed time, which makes the guard stricter rather than laxer.

### Fall back to elapsed time when the field is absent

A document written before this change has no accumulated total. Rejecting those hosts would make the fix look like a regression on its first deploy.

*Consequence accepted:* for one window's worth of samples after deploy, a host is judged by the old, wrong denominator. compute5-prod therefore stays `unknown` until it has accumulated enough observed time to be judged on it. That is a delay, not an error.

### Both consumers change in the same commit

They are required to agree by spec. Changing one alone produces a period where the report and the dashboards disagree about which hosts have usable evidence, which is the failure the pairing exists to prevent.

## Risks / Trade-offs

- **Counts move, and the movement is not remediation** → compute5-prod's 137 undetermined findings become assessable, so not-affected and open rise. Belongs in `elastinix-e79k` before the next report.
- **The threshold is a guess** → three intervals is untested against real jitter. A week of fleet data would show whether slow samples cause false gaps. The direction of error is safe.
- **A host stopped for a very long time accumulates almost nothing** → an instance stopped for a month gains one interval per restart, so its window grows slowly and its evidence stays thin. That is the true state of the evidence.
- **Still no bound on what a short window can claim** → this change makes the guard measure the right thing; it does not stop a 3-day window from justifying a negative. `elastinix-sw3u` owns that, and until it lands the report continues to publish not-affected verdicts from windows that may be too short.
- **The fourth duplicated rule gets another edit** → both copies must stay identical. The spec requires it; nothing enforces it.

## Migration Plan

1. Deploy the sampler change. Accumulation begins at the next sample; nothing else moves.
2. Let each host accumulate for at least one window before deploying the guard change, so the fallback path is not the one being exercised.
3. Deploy the guard in the normalizer and exporter together. Counts move here.
4. Record the movement in `elastinix-e79k` before the next review report.

Rollback: reverting the guard restores the previous labels. The accumulated field is additive and can stay.
