---
# elastinix-66ao
title: Not-affected verdicts are published from a window shorter than the host's own job cadences
status: scrapped
type: bug
priority: critical
created_at: 2026-08-28T13:07:25Z
updated_at: 2026-08-28T13:20:56Z
parent: elastinix-p9gu
---

The report publishes 79 fleet findings as not affected, justified vulnerable_code_not_in_execute_path with the basis "never observed in N samples". The observation window does not support that claim.

## Evidence (compute2-prod, 2026-08-28)

  observation window   2026-08-25T13:44:51Z -> 2026-08-28T12:18:31Z  = 2d 22h 34m
  samples              810

Timers on that same host:

  jiraticketcreate-technative-zammad-tn-zammad-lifecycle-quarterly.timer   quarterly
  jiraticketcreate-iit-iit-medux-monthly-report.timer                      monthly
  jiraticketcreate-iit-iit-zammad-monthly-report.timer                     monthly
  jiraticketcreate-technative-iso-tn-iso-815logging-monthly.timer          monthly
  badgersbay.timer                          last run 2026-07-31, 4 weeks ago
  fstrim.timer                                                             every 2 days

Any package whose only consumer is the quarterly job has never been observed and is
published as not affected. The claim is false and an auditor can disprove it with
systemctl list-timers. "810 samples" also reads as broad coverage while concealing
that the window is three days.

## Approach

The host knows the answer. Derive the longest scheduled timer interval as a HASP
derived fact. When the observation window is shorter than that interval, a false
in-use reading cannot be trusted, so the normalizer downgrades inUse false to
unknown and records the window, the sample count and the longest cadence.

Self-adjusting per host, and more defensible than an arbitrary minimum window.

## Why the downgrade belongs in the normalizer

The report tool lives in the isotto repo and presents only. The Prometheus exporter
lives in elastinix and emits the same inuse label. If the rule were implemented in
the report, dashboards would keep claiming inuse=false while the report said
undetermined -- the exact contradiction the shared guard exists to prevent.

Deciding in the normalizer gives one implementation. Every consumer inherits it.

## Supersedes

openspec/changes/in-use-code-sampling task 7.2, "Let observations accumulate before
presenting false as evidence; record the window used".

## Resolved by elastinix-yx3a

The concern was right even though the evidence cited was wrong: a negative claim
was resting on a window nobody had chosen. Bucketing observation per day and
aggregating per month makes the window the reporting period, which is what this
bean was reaching for.
