## Context

`modules/nixos/services/service-badgersbay.nix` ends with two unit declarations
for one program:

```
  badgersbay.service   Type=simple, wantedBy=multi-user.target,
                       Restart=on-failure, RestartSec=10s
  badgersbay.timer     OnCalendar=hourly, Persistent=true,
                       wantedBy=timers.target
```

A timer with no `Unit=` fires the service of the same name, so `badgersbay.timer`
runs `systemctl start badgersbay.service` every hour at a service that is
started at boot and meant to stay up.

## What the history says it was for

| Commit    | Date       | Subject                          | What it did                    |
|-----------|------------|----------------------------------|--------------------------------|
| `418ba25` | 2026-03-27 | restart badgersbay service hourly | Added the timer at 03:00 daily, in the same commit that dropped the tmpfiles copy of `config.yaml` and pointed `--config` at `configFile` |
| `1cfd50c` | 2026-04-08 | update schedule for badgersbay    | `*-*-* 03:00:00` → `hourly`     |

The subject of the commit that introduced it says "restart ... hourly", the
schedule it actually set was daily, and the body of neither commit explains
anything. Two weeks later the interval was shortened.

Read together with what else `418ba25` changed - the configuration stopped being
copied to a path the module controlled and started being read from wherever
`configFile` pointed - the timer is a workaround for a daemon that reads its
configuration once. It is the same problem `restartTriggers` solves, addressed
before anyone had named it.

## The mechanism it was missing

A `systemd.timer` *starts* its unit. `systemctl start` on a unit that is already
active does nothing at all - it does not restart, reload, or signal the process.
So the hourly firing has never once caused badgersbay to re-read a file.

That explains the escalation. Daily did not take effect, so it became hourly,
which also did not take effect, and nothing about either failure was visible:
`systemctl list-timers` shows the timer firing on schedule, and the service it
fires at is active, so both look correct. It ended with compute2 serving a
configuration from hours earlier on 2026-09-16 (elastinix-qxvt) - a symptom an
hourly restart would have bounded to an hour, had the timer been one.

Had the timer been written as a restart - a oneshot unit running `systemctl
restart badgersbay`, say - it would have worked, and it would then have masked
elastinix-qxvt by making the staleness intermittent and self-healing. The timer
being broken is the only reason that bug was diagnosable.

## Decisions

### Remove the timer rather than repair it

The bean allowed for either: drop it, or give periodic work its own unit if any
turned out to exist. None does. `honeybadger_server.py` takes five arguments -
`--config`, `--token-file`, `--dashboard-password-file`, `--asset-register`,
`--version` - and has no batch mode, no scheduler, no `--once`, and no signal
handler (the only `reload()` calls in the file are JavaScript in the dashboard
it serves). It is an HTTP server and nothing else.

Nothing references the timer either: not the module, not
`docs/services/badgersbay.md` - which already describes the service as "a daemon
(Type=simple)" and never mentions a timer - and no host configuration in this
repository.

| Alternative                              | Why not                            |
|------------------------------------------|------------------------------------|
| Keep it, fix it to restart               | Would work, and would have masked elastinix-qxvt; `restartTriggers` already restarts on the only thing worth restarting for |
| Keep it as a crash-recovery net          | See below                          |
| Give it `Unit = <oneshot>` batch job     | There is no batch job              |

### Let a failed unit stay failed

One thing is actually being removed. A timer pointed at an active-by-design unit
does nothing *while the unit is active* - but if badgersbay exhausts its restart
limit (five starts in ten seconds, systemd's default) and lands in `failed`, the
next hourly firing starts it again. The timer has been an accidental
hourly resurrection.

Not worth keeping, and not replaced:

- The failures this service has are not transient. The module's assertions catch
  a misdelivered secret at evaluation; what is left to fail at runtime is a
  register the server refuses, a port already taken, an unreadable secret. None
  of those is fixed by waiting an hour.
- A unit in `failed` is a signal. `elastinix.services.systemd-monitoring`
  checks `Active: active` every ten minutes and logs when a service "encountered
  issues", for any service a host lists. A unit resurrected hourly and failing
  again produces the same log line plus an hourly restart that looks like
  recovery.

`StartLimitIntervalSec = 0` is the honest version of a recovery net - retry
every ten seconds, forever - and is deliberately not part of this change. It
converts a permanent failure into perpetual noise, and changing the restart
policy is a decision on its own, not a side effect of deleting a timer that did
nothing.

## Risks / Trade-offs

- **A crash-looping badgersbay now needs a person or a deploy.** Above.
- **Someone may add the timer back** the next time a changed file appears not to
  take effect - which is exactly how it arrived. The spec requirement is the
  guard: it records that this unit is a daemon, that a timer cannot reload it,
  and where periodic work would go instead.

## Verification

No in-tree test harness exists for service modules. Verified by evaluating the
module out of tree against the real flake inputs, as compute2 configures it:

1. `config.systemd.timers ? badgersbay` is false, and no `badgersbay.timer`
   appears among the units the system builds - checked against the same
   evaluation at `HEAD`, where both are present.
2. `badgersbay.service` is untouched: the built unit file is byte-identical to
   the one built before the removal, so nothing about the daemon changed.
3. `system.build.toplevel` instantiates, so the assertions still pass, and the
   built `etc/systemd/system` contains `badgersbay.service` and no
   `badgersbay.timer`.
