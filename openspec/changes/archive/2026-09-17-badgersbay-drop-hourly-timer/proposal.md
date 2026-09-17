## Why

The module declares badgersbay twice over: a long-running daemon, and an hourly
timer pointed at it.

```nix
systemd.services.badgersbay = {
  wantedBy = [ "multi-user.target" ];       # start at boot, stay up
  serviceConfig.Type = "simple";
  serviceConfig.Restart = "on-failure";
};

systemd.timers.badgersbay = {
  wantedBy = [ "timers.target" ];
  timerConfig = { OnCalendar = "hourly"; Persistent = true; };
};
```

The history says what the timer was for. It arrived in `418ba25`, whose subject
is *"restart badgersbay service hourly"*, in the same commit that removed the
`systemd.tmpfiles` rule copying the configuration into
`${storagePath}/config.yaml` and pointed `--config` straight at `configFile`.
Two weeks later `1cfd50c` escalated it from `*-*-* 03:00:00` to `hourly`.

So it was never a periodic job. It was a hand-rolled attempt to make a daemon
that reads its files once pick up a changed configuration - the same problem
`restartTriggers` now solves properly (`d9ed86c`, elastinix-qxvt).

And it never worked. A timer *starts* its unit, and `systemctl start` on an
already-active `Type = "simple"` service is a no-op. The escalation from daily
to hourly is what that looks like from the outside: the interval got shorter
because nothing was taking effect. compute2 then ran a stale configuration for
hours on 2026-09-16 - which an hourly restart, had it been one, would have
bounded to an hour.

## What Changes

- **`systemd.timers.badgersbay` is removed.** No periodic run is wanted: the
  server takes five arguments, has no batch mode, no scheduler and no signal
  handler, and does nothing but serve HTTP. Nothing in the repository or the
  documentation references the timer.
- Nothing replaces it. The need it was reaching for is met by the
  `restartTriggers` already on the unit.

## Capabilities

### Modified Capabilities
- `badgersbay-service`: records that the module configures a daemon and not a
  periodic job, so an hourly timer is not added back the next time a changed
  file appears not to take effect

## Impact

- **The unit list stops lying.** `badgersbay.timer` made the service look
  periodic to anyone reading it, and it was the first thing ruled out while
  chasing elastinix-wckg. It cost reading time and bought nothing.
- **One behaviour is genuinely lost**: a badgersbay that exhausts its restart
  limit and lands in `failed` is currently started again by the next hourly
  firing - the one case where a timer pointed at an active-by-design unit does
  something. That resurrection is not worth keeping. A service that fails five
  times in ten seconds fails for a reason, and the module's own assertions plus
  the server's refusal to start on an untrustworthy asset register are exactly
  such reasons. A unit sitting in `failed` is a signal, which
  `elastinix.services.systemd-monitoring` reports on if the host lists
  badgersbay; a unit resurrected hourly and failing again is noise that looks
  like recovery.
- No change to the service unit itself, and no host configuration to update.

## Non-goals

- **Making the restart policy more persistent.** Dropping the timer removes a
  crude recovery path, and `StartLimitIntervalSec = 0` would be the honest
  replacement - systemd retrying every 10 seconds forever instead of hourly.
  Not done here: it trades a clean `failed` state for perpetual retry noise on
  a permanent failure, and it is a deliberate decision about restart policy
  that no incident has asked for. This change is about removing something that
  does nothing, not about changing what happens when the service dies.
- **A health check.** The docs suggest a `badgersbay-health` timer as an
  example, and something on compute2 polls the dashboard every 30 seconds
  without credentials. That is elastinix-wckg, and it is not this timer.
- **Periodic work in badgersbay.** If the server ever gains a batch job, it
  gets its own `Type = "oneshot"` unit and its own timer rather than sharing
  the daemon's.

## Tracking

- Bean: [elastinix-po09](../../../.beans/elastinix-po09--badgersbay-an-hourly-timer-points-at-a-long-runnin.md)
