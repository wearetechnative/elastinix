---
# elastinix-po09
title: 'badgersbay: an hourly timer points at a long-running service'
status: todo
type: bug
priority: normal
tags:
    - badgersbay
    - systemd
created_at: 2026-09-17T13:49:14Z
updated_at: 2026-09-17T13:49:14Z
---

The module declares both:

```nix
systemd.services.badgersbay = {
  wantedBy = [ "multi-user.target" ];
  serviceConfig.Type = "simple";
  serviceConfig.Restart = "on-failure";
};

systemd.timers.badgersbay = {
  wantedBy = [ "timers.target" ];
  timerConfig = { OnCalendar = "hourly"; Persistent = true; };
};
```

A `Type = "simple"` unit that is `wantedBy multi-user.target` with `Restart =
"on-failure"` is a daemon: it is already running, and it is meant to be. An
`OnCalendar = "hourly"` timer pointed at that same unit asks systemd to start
something that is never stopped. One of the two is wrong.

## Why it is worth deciding rather than leaving

The timer is not harmless. `systemctl start` on an active simple service is a
no-op, so the hourly firing does nothing visible - but it makes the service look
periodic to anyone reading the unit list, and `badgersbay.timer` was the first
thing ruled out while chasing elastinix-wckg. A timer that means nothing costs
reading time every time someone looks.

It would also have masked elastinix-qxvt if the service had been anything but
`simple`: an hourly restart hides a missing restartTrigger for up to an hour and
makes the symptom intermittent, which is worse to diagnose than a symptom that
never goes away.

## To establish

- Whether anything actually wants a periodic badgersbay run. The server is an
  HTTP endpoint that hosts submit to; nothing in the module suggests batch work.
- Whether the timer predates the service being a daemon - it may be a leftover
  from a one-shot report-collection design.

## To fix

Drop `systemd.timers.badgersbay`, unless the first question above turns up a
periodic job, in which case it needs its own oneshot unit rather than sharing
the daemon.

## Origin

Noticed while fixing elastinix-qxvt and recorded there under "Unrelated, but
noticed in the same place". Not investigated, and explicitly not offered as the
cause of that bug.
