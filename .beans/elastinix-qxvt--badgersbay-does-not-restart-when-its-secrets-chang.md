---
# elastinix-qxvt
title: badgersbay does not restart when its secrets change
status: todo
type: bug
priority: high
tags:
    - badgersbay
    - agenix
created_at: 2026-09-17T13:22:32Z
updated_at: 2026-09-17T13:22:32Z
---

The module declares no `restartTriggers` on the files it passes to the server.
badgersbay reads its configuration, its tokens, its dashboard password and its
asset register once, at startup. agenix rewrites those files during activation.
Nothing connects the two.

So a deploy that changes a secret lands on disk and never reaches the running
process. terraform is satisfied, `/run/current-system` is correct, the unit file
is correct, and the service keeps serving what it read the last time it started.
No log line says anything is out of date.

## Seen, not theorised

On 2026-09-16 compute2 ran the new server against an old configuration for
hours. The dashboard showed the legacy view because `compliance.enabled` was
false in the configuration the process had in memory, while the file on disk
said otherwise. A manual `systemctl restart badgersbay` fixed it immediately.

It cost an evening of looking in the wrong place: the closure was new, the unit
was new, and the symptom looked like a deployment that had not happened.

## Why it gets worse rather than better

A rotated token is the case to worry about. The new token file is written, the
service keeps accepting the old one and rejecting the new one, and both
behaviours look like the system working. Nobody checks a token that still works.

The asset register has the same shape: it is replaced when people join, leave or
swap machines, and a register that silently does not take effect produces a
compliance figure that is quietly out of date.

## Fix

Add `restartTriggers` covering `configFile`, `tokenFile`,
`dashboardPasswordFile` and `assetRegisterFile`. For an agenix path the file
content is not readable at evaluation, so trigger on the path and on the
`age.secrets` entry that produces it.

## Unrelated, but noticed in the same place

`systemd.timers.badgersbay` runs `OnCalendar = "hourly"` against a service that
is `Type = "simple"` with `Restart = "on-failure"` and `wantedBy
multi-user.target` - a long-running service with an hourly timer pointed at it.
One of the two is wrong. Not investigated, and not offered as the cause of the
above.
