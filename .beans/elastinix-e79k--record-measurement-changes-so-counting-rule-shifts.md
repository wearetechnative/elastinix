---
# elastinix-e79k
title: Record measurement changes so counting-rule shifts are not read as remediation
status: scrapped
type: task
priority: high
created_at: 2026-08-28T13:07:42Z
updated_at: 2026-08-31T10:48:05Z
parent: elastinix-p9gu
---

Four separate re-baselining events are in flight, and nothing records any of them:

  1. nixified-optscale removed from compute1-prod. 52 -> 22 vulnerable packages,
     211 -> 124 distinct CVEs. A temporary install with a large package surface.
  2. Multi-output dedup fix (fix-cve-overcounting). ~44% drop in reported instances.
  3. summary.packages corrected to exclude packages whose every CVE was
     vendor-excluded. compute2 38 -> 34, compute1 56 -> 52, compute5 40 -> 34.
  4. Patch-content CVE extraction, still pending (fix-cve-overcounting task 7.1).
     Predicted compute5 471 -> 446, compute2 365 -> 335.

Only the first is a real reduction in exposure. The other three are measurement
changes. An auditor comparing this quarter to next sees dramatic improvement that
is mostly not remediation, which is worse than reporting no trend at all because it
is an unearned claim.

fix-cve-overcounting task 6.2 already asks for this for its own drop: "Annotate
dashboards at cutover and record the re-baseline so the 44% drop is not later read
as remediation". It is still open, and the problem has since grown from one event
to four.

## Approach

Human-curated state in git that the report renders, same argument as the verdict
register: a commit carries author, date, diff and reviewer, which is the evidence
chain ISO 27001 wants.

Each entry needs the date, what changed, whether it was exposure or measurement,
the affected hosts and the before/after figures. The review report gains a
Measurement Changes section listing entries in the reporting period, so a reader
cannot mistake a counting change for progress.

Open question: whether the file lives in elastinix beside the scanner or in isotto
beside the report. It is read by the report, written by whoever changes a rule.

## Entries to record, measured 2026-08-31

Real reduction in exposure — this one can be claimed:

- compute5-prod critical+high 137 -> 94, because ten packages left the closure on
  redeploy: openssl-3.6.0, glibc-2.40-66, perl-5.40.0, sqlite-3.50.4, curl-8.17.0,
  zlib-1.3.1, go-1.25.4, hugo-0.152.2, nghttp2-1.67.1, ngtcp2-1.17.0. Older
  duplicate versions and the quiqr toolchain, garbage-collected out.
- compute1-prod vulnerable packages 52 -> 22 and distinct CVEs 211 -> 124, from
  removing the temporary nixified-optscale install.

Measurement changes — these are not remediation:

- compute5-prod undetermined 137 -> 0, from the in-use liveness guard being
  measured against observed rather than elapsed time (elastinix-slry). The findings
  were always there; they simply could not be assessed.
- summary.packages corrected to exclude packages whose every CVE was
  vendor-excluded: compute2 39 -> 35, compute1 26 -> 22, compute5 42 -> 36.
- Multi-output deduplication (elastinix-krg3), roughly a 44% drop in reported
  instances.
- Profile hashes changed on all three hosts twice in one week because the HASP
  registry version changed, not because any host changed.

Still pending and predicted: patch-content CVE extraction (fix-cve-overcounting
task 7.1), compute5 471 -> 446 and compute2 365 -> 335.

## Partly addressed by elastinix-yx3a

Closed as out of scope because S3 already holds an immutable bundle per run, so what
moved is reconstructable. Daily buckets aggregated per month add the missing half:
bounded periods make month-on-month comparison possible at all, and a daily record
of the prevailing profile hash makes a hash change explicable rather than alarming.
Neither replaces a human judgement about whether a drop was exposure or measurement.
