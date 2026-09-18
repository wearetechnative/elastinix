## ADDED Requirements

### Requirement: Run as a daemon, not a periodic job

The module SHALL configure badgersbay as a single long-running service and SHALL
NOT declare a timer that starts it on a schedule. The server serves HTTP and has
no batch mode; a changed file reaches it through the unit's `restartTriggers`,
not through a periodic restart.

Should badgersbay ever gain periodic work, it SHALL be given its own
`Type = "oneshot"` unit and its own timer rather than a timer pointed at the
daemon.

#### Scenario: The units the module declares
- **WHEN** the service is enabled
- **THEN** `badgersbay.service` is declared and no `badgersbay.timer` exists

#### Scenario: A changed file
- **WHEN** the configuration, a token, the dashboard password or the asset
  register changes
- **THEN** the restart comes from `restartTriggers` at deploy time, not from
  waiting for a scheduled restart

#### Scenario: A timer pointed at a running daemon
- **WHEN** a timer fires at a `Type = "simple"` unit that is already active
- **THEN** nothing happens, because a timer starts its unit and starting an
  active service is a no-op - which is why such a timer cannot serve as a
  configuration reload and must not be added as one

#### Scenario: A service that has exhausted its restart limit
- **WHEN** badgersbay fails repeatedly and systemd stops retrying, for example
  on an asset register the server refuses
- **THEN** the unit stays `failed` and visible to whatever watches units, rather
  than being started again on a schedule and failing again for the same reason
