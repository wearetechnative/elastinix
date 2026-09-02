---
# elastinix-sw3u
title: Decide how to bound a negative in-use claim, given timer cadence understates work cadence
status: draft
type: task
priority: high
created_at: 2026-08-28T13:20:56Z
updated_at: 2026-08-28T13:20:56Z
parent: elastinix-p9gu
---

Replaces elastinix-66ao, which was scrapped because its evidence was wrong.

## The problem is real

The report publishes findings as not affected, justified vulnerable_code_not_in_execute_path, from a 3-day observation window. Nothing checks whether the window could have observed the code.

## The correction

elastinix-66ao claimed compute2-prod runs a quarterly timer. It does not. Verified on the host:

  jiraticketcreate-technative-zammad-tn-zammad-lifecycle-quarterly.timer   OnCalendar=daily
  jiraticketcreate-iit-iit-medux-monthly-report.timer                      OnCalendar=daily
  badgersbay.timer                                                        OnCalendar=hourly

The unit NAMES say quarterly and monthly. Every timer fires daily or hourly; the
scripts decide internally whether today is the right day. badgersbay.timer last ran
four weeks ago on an hourly schedule, so that is a failed or disabled unit rather
than a rare one.

Complete set of cadences on compute2-prod: 02:15, *:0/30, hourly, daily, weekly.
The longest is weekly.

## Why this killed the first approach

The scrapped design derived runtime.longestScheduledIntervalSeconds from timer
configuration and treated it as the yardstick a negative claim must clear. But the
real cadence of work lives inside the scripts, invisible to systemd. A daily timer
running a quarterly report means quarterly code paths that no timer cadence reveals.

The fact would have reported 604800 for compute2, the 3-day window would still have
failed it, and the mechanism would have appeared to work while silently missing the
monthly and quarterly code paths it existed to catch. A defensible-looking number
that does not measure what was claimed is worse than the current visible gap.

## Direction agreed

Keep a cadence fact, but state honestly what it bounds: the longest TIMER interval,
explicitly not the cadence of work inside units. The window rule becomes a floor
rather than a proof, and the report says so.

Options still open:
- observational instead of declarative: the sampler already records which units hold
  which packages, so a package first observed on day 60 of a 90-day window
  demonstrates that window length matters. Measures the real thing, but says nothing
  until the window is long.
- a policy minimum window. Arbitrary, but does not pretend to be derived.

Supersedes openspec/changes/in-use-code-sampling task 7.2.

## Superseded by elastinix-yx3a

Bounding a negative claim by the host's own job cadence was the wrong instrument,
and the correction recorded above is why. The right bound is the reporting period:
observation is bucketed per day and aggregated per month, so the window a verdict
rests on is the month the report covers rather than whatever has elapsed since the
last reset. Nothing on this fleet runs less often than monthly, so the cadence
question that killed the first two approaches does not arise.

Kept open only until elastinix-yx3a is written up as a change; it carries the
evidence for why the two earlier instruments were rejected.
