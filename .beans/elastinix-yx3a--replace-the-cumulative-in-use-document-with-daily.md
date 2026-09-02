---
# elastinix-yx3a
title: Replace the cumulative in-use document with daily buckets, aggregated per month
status: completed
type: task
priority: high
created_at: 2026-08-31T11:15:23Z
updated_at: 2026-09-02T08:24:15Z
parent: elastinix-p9gu
openspec-link: openspec/changes/archive/2026-09-02-daily-observation-buckets
---

Observation currently accumulates forever into one document per host. The window a
negative claim rests on is therefore whatever has elapsed since the last reset,
which is a deploy artefact rather than a period anyone chose. ISO reporting here is
monthly, so the evidence should be too.

## What this fixes

**The window becomes the reporting period.** Today the report says "never observed
in 804 samples", which sounds like broad coverage and is 68 hours. With daily
buckets it says "not observed during August, 27 of 31 days fully observed", which
is a claim an auditor can weigh.

**Coverage becomes expressible.** At the 300 second interval a full day is 288
samples, so per day the fraction observed is a fact rather than an impression.

**Three defects disappear structurally rather than being patched.** Ephemeral
client ports accumulating as listeners (elastinix-ytnc), the coverage numerator and
denominator covering different periods, and the epoch reset needed to repair a pair
that had drifted (elastinix-slry) all came from one forever-growing document whose
fields fell out of step. A bucket that is sealed at the end of its day has nothing
to drift against, and no migration path where old and new state coexist. All three
of those defects were found only after deploying.

**Trend becomes possible.** Comparing month to month requires bounded periods.
There are none today, which is part of why elastinix-e79k was closed.

**A profile change becomes explicable.** A daily record of the prevailing haspHash
lets the report say "the profile of compute2-prod changed once this month, on the
28th" instead of showing a changed hash an auditor cannot place.

## Cost

A bucket holds only that day, so it is smaller than todays 29.9 kB
runtime-facts.json with 139 packages and 14 socket keys. Roughly 20 kB per host per
day, about 7 MB per host per year, and the month can be summarised into one file
once it is closed.

## Decided

- Observation is bucketed per day. A bucket is immutable once its day is over.
- An isotto tool fetches every day of the month and aggregates them. Run by hand
  by the reviewer, like the other compliance tools.
- The existing cumulative set is discarded rather than migrated. Carrying two
  differently shaped sets of facts is worse than one gap.
- Nothing on this fleet runs less often than monthly, so a month-long window is
  sufficient in practice. The report still states the window rather than implying
  coverage.


**Roles.** The host seals a day's bucket when the day rolls over; it is the only
party observing continuously, and the scanner visits weekly. The scanner fetches
every bucket it has not uploaded and writes it to S3. Retention lives on the S3
bucket. Isotto reads from S3 and aggregates the month.

**Upload is idempotent without state.** Each bucket gets a deterministic key,
`daily/<host>/<date>.json`, and the existing conditional write skips one that
already exists. Nothing has to track what was uploaded, and it works unchanged
against the write-only IAM policy already in place.

**One record per host per day** carries all four facts: that day's in-use
observations, that day's socket observations, the prevailing `haspHash`, and the
`hasp-aws` values with their `changedKeys`. One daily series rather than four.

**A full day is all uptime within that day, not 24 hours of it.** Measured:

    host             uptime/day   max samples   of 288   schedule
    compute1-prod      24.0 h         288        100%    -
    compute2-prod      24.0 h         288        100%    -
    compute5-prod      15.5 h         186         64%    6:30am-to-10pm-everyday

compute5-prod is stopped 8.5 hours every night, so a 24-hour definition would mark
it incomplete every day forever while its sampler works perfectly. That is the same
error as the liveness guard measuring against elapsed time, which cost three deploys
to find and correct. The bucket records the hours it observed as a fact; the report
states them rather than treating them as a shortfall.

**Downtime is distinguishable from a stalled sampler, and must be.** Both produce a
gap, so without a discriminator "all uptime observed" cannot be verified. The
sampler reads `/proc/uptime` on each run and stores it. When the gap since the
previous sample exceeds the threshold:

- uptime shorter than the gap means the host rebooted, so the gap is downtime and
  the day stays complete
- uptime longer than the gap means the host was running and the sampler was not, so
  the day is incomplete and says so

Verified on compute5-prod: uptime 6.9 h puts boot at 04:31 UTC, which matches the
06:30 CEST schedule exactly, so the reading is trustworthy.

## Still to settle during implementation

- Whether a single missed sample makes a day incomplete, or whether a tolerance
  applies. Reaching 288 requires that nothing is ever missed, which is strict for a
  monthly figure.
- Whether the host keeps its sealed buckets after upload. Retention is on S3, so
  nothing forces the host to prune; at roughly 20 kB a day that is about 7 MB a
  year, which is harmless but should be a decision rather than an oversight.
- How a day is sealed across a reboot that straddles midnight.

## Relation to other beans

Supersedes the approach in elastinix-sw3u: bounding a negative claim by the hosts
own job cadence was the wrong instrument, and bounding it by the reporting period
is the right one. Also supersedes in-use-code-sampling task 7.2, "let observations
accumulate before presenting false as evidence; record the window used".
