## Context

See proposal.md — Why.

Constraints:

- The sampler runs every 300 seconds. A full calendar day is therefore 288 samples, but compute5-prod carries `InstanceScheduler = "6:30am-to-10pm-everyday"` and is stopped 8.5 hours a night, so its ceiling is 15.5 hours and 186 samples. compute1-prod and compute2-prod have no scheduler.
- The scanner visits weekly with up to six hours of jitter. Only the host observes continuously, so only the host can close a day.
- hostinfo serves `/var/lib/hostinfo` with `python3 -m http.server`. It is a static file server, so anything a consumer reads must exist as a file.
- The exporter and the normalizer duplicate the coverage rule deliberately, kept in step by spec rather than by shared code. This change touches it in both.
- `hasp.json` is a pure build product and must stay one. A daily record may name the hash in force; it may not compute one.
- Three defects this month came from a document that accumulated forever and whose fields fell out of step, each found only after deploying.

## Goals / Non-Goals

**Goals:**

- The period a negative claim rests on is the period the report covers.
- A host deliberately stopped is distinguishable from a sampler that has died, from the record alone.
- A sealed record needs no migration, ever.

**Non-Goals:**

- The monthly aggregation. That is an isotto tool reading S3, and it depends on records being there first.
- Preserving the existing cumulative evidence. Discarded deliberately.
- Reducing code. The sampler gains day handling and the consumers lose the window machinery; the win is that the evidence answers the question that is actually asked.

## Decisions

### The host seals, the scanner uploads

The sampler closes a day when it observes that the date has changed. The scanner fetches whatever sealed records it finds and uploads each.

*Alternative considered:* have the scanner build the daily records. It visits weekly, so six days in seven would have no record at all. Only the party that observes continuously can bound a day.

### A complete day is all uptime, not 24 hours

Measured on the fleet:

    host             uptime/day   max samples   of 288
    compute1-prod      24.0 h         288        100%
    compute2-prod      24.0 h         288        100%
    compute5-prod      15.5 h         186         64%

A 24-hour definition marks compute5-prod incomplete every day forever while its sampler works perfectly. That is the same error as the liveness guard measuring against elapsed time, which took three deploys to find and correct, and it would be reintroduced deliberately this time.

*Consequence accepted:* the record must state the hours it observed, so a reader sees 15.5 rather than inferring 100% of something unstated. Completeness and duration are two facts, not one.

### `/proc/uptime` attributes the gap

Downtime and a stalled sampler both produce a gap. Without a discriminator, "all uptime observed" cannot be verified and the definition above is unfalsifiable. The sampler records uptime each run; when a gap exceeds the threshold, uptime shorter than the gap means a reboot and uptime longer means the sampler stopped while the host ran.

Verified on compute5-prod: uptime 6.9 h places boot at 04:31 UTC, matching the 06:30 CEST schedule exactly.

*Consequence accepted:* two reboots inside one gap are indistinguishable from one, and a host stopped and started repeatedly within a gap under-reports its downtime. Both err toward marking the day incomplete, which is the safe direction.

### Sealed records are immutable, and that is the point

Once a day ends its record is never written again.

Every defect this month — ephemeral ports growing the socket set without bound, a lifetime sample count divided by a fresh window, an epoch marker added to repair a pair that had drifted — came from one document that was still being modified after the facts in it were established. A sealed record has no such window. There is also no migration path in which old and new state coexist, which is where all three defects actually surfaced.

### The existing evidence is discarded, not converted

Every host starts an empty series.

*Alternative considered:* synthesise a day-zero record from the current cumulative set. It would carry 139 packages with no defensible date range, and it would be the only record in the series whose period is unknown — the exact property this change removes.

*Consequence accepted:* for one day no host can support a negative claim, so every finding reports `inUse: "unknown"`. That is visible and temporary. It must be recorded before the next monthly report, or a reader sees not-affected counts collapse to zero and reads it as a defect.

### Both consumers change together

The normalizer and the exporter derive coverage identically and must continue to. They are required to by spec; nothing enforces it, and this is the fourth rule they share.

## Risks / Trade-offs

- **A one-day gap in negative claims on deploy** → deliberate, stated above, and it must be written down before the next report rather than explained afterwards.
- **Day boundaries are UTC while the fleet's schedule is CEST** → compute5-prod's stop at 22:00 CEST is 20:00 UTC, so its uptime straddles no midnight and the arithmetic is unaffected. A host stopped across UTC midnight would split its uptime over two records, each correctly reporting its own portion.
- **A reboot straddling midnight** → the first sample after it belongs to the new day, and the previous day is sealed with whatever it observed. The seal happens on first observation of a new date, so a host down across midnight seals the previous day late but correctly.
- **The threshold that separates a slow sample from a gap** → inherited from the current sampler at three intervals. Unchanged, and the same trade-off: too small and jitter reads as downtime, too large and a real outage is credited as observation.
- **A missed sample makes a day incomplete under a strict reading** → 288 requires that nothing is ever missed, which is severe for a monthly figure. Whether a tolerance applies is left to implementation and must be decided explicitly rather than defaulted.
- **Records accumulate on the host** → retention is on S3, so nothing prunes the host. At roughly 20 kB a day that is about 7 MB a year, harmless but a decision rather than an oversight.
- **The fourth duplicated rule between normalizer and exporter** → this change makes the case for extracting them stronger without acting on it.

## Migration Plan

1. Land the sampler change. Hosts begin sealing daily records; the cumulative document stops being written and the evidence gap begins.
2. Land the scanner fetch and upload together with the coverage change in the normalizer and the exporter, so a bundle is never built from records nobody judges.
3. Record the one-day gap and the reset of the in-use baseline before the next monthly report.
4. Add the S3 lifecycle rule for the `daily/` prefix in Terraform.
5. Build the isotto aggregation tool once a month of records exists in S3.

Rollback: reverting the sampler restores the cumulative document, but the days already sealed are not converted back and the cumulative set restarts empty. Rollback therefore costs the same gap a second time; the sampler change is the point of no return.
