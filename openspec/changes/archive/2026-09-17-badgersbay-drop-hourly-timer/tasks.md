## 1. The module

- [x] 1.1 Remove `systemd.timers.badgersbay`, and with it the trailing
      whitespace the block carried
- [x] 1.2 Leave `systemd.services.badgersbay` untouched - the daemon is the
      half that was right

## 2. Verification

- [x] 2.1 Evaluate compute2-shaped: `systemd.timers ? badgersbay` is false,
      against the same evaluation at `HEAD` where it is true
- [x] 2.2 Build the service unit before and after; assert it is byte-identical,
      so removing the timer changed nothing about the daemon
- [x] 2.3 Instantiate `system.build.toplevel` so the assertions are forced
- [x] 2.4 Build the system's `etc/systemd/system` and assert it contains
      `badgersbay.service` and no `badgersbay.timer`, and that no `timers.target`
      wants it

## 3. Docs

- [x] 3.1 `docs/services/badgersbay.md`: record that the service is a daemon
      with no timer, that a timer cannot make it re-read its files, and where
      periodic work would go - the docs never documented the timer, so this
      states the shape rather than removing a mention
