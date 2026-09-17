## Why

Badgersbay reads its configuration, its API tokens, its dashboard password and
its asset register once, at startup. agenix rewrites those files during
activation. Nothing in the module connects the two: `systemd.services.badgersbay`
declares no `restartTriggers`.

The unit's `script` interpolates the paths, so for a *generated* configuration -
a nix store path that changes with its content - the unit changes and systemd
restarts the service. Every other file arrives from agenix at a stable path:
`/run/agenix/badgersbay-tokens` is the same string before and after the rewrite.
The unit does not change, the service is not restarted, and the process keeps
serving what it read the last time it started.

A deploy therefore lands on disk and never reaches the running process.
terraform is satisfied, `/run/current-system` is correct, the unit file is
correct, and no log line says anything is out of date.

## Seen, not theorised

On 2026-09-16 compute2 ran the new server against an old configuration for
hours. The dashboard showed the legacy view because `compliance.enabled` was
false in the configuration the process had in memory, while the file on disk
said otherwise. compute2 overrides `configFile` with an agenix secret, so the
one file that would otherwise have triggered a restart did not either. A manual
`systemctl restart badgersbay` fixed it immediately.

It cost an evening of looking in the wrong place: the closure was new, the unit
was new, and the symptom looked like a deployment that had not happened.

A rotated token is the case to worry about. The new token file is written, the
service keeps accepting the old one and rejecting the new one, and both
behaviours look like the system working. Nobody checks a token that still works.
The asset register has the same shape: it is replaced when people join, leave or
swap machines, and a register that silently does not take effect produces a
compliance figure that is quietly out of date.

## What Changes

- **`restartTriggers` on every file the server reads at startup**: `configFile`,
  `tokenFile`, `dashboardPasswordFile` and `assetRegisterFile`.
- **For an agenix path, trigger on the encrypted source as well.** The decrypted
  content is not readable at evaluation and the path is stable, so the path
  alone is not a trigger. The `age.secrets` entry's `file` - the `.age`
  ciphertext, a store path - is what changes when the secret is edited, and it
  is already public.
- **Documentation** of what the triggers cover, and of the one case they cannot:
  a secret file that neither lives in the store nor is declared to agenix.

## Capabilities

### Modified Capabilities
- `badgersbay-service`: gains a requirement that a changed input reaches the
  running process

## Impact

- A deploy that changes any of the four files now restarts badgersbay, after
  agenix has written the new content. `switch-to-configuration` stops the units
  it must restart, runs the activation scripts, and only then starts them, so
  the restarted process reads the new file rather than the old one.
- Re-encrypting a secret produces different ciphertext even when the plaintext
  is unchanged, so `agenix -e` with no edit restarts the service. Deliberate: a
  restart nobody needed is a few seconds of downtime, a restart that did not
  happen is the bug above.
- No change for a host that changes nothing.

## Non-goals

- **The hourly timer.** `systemd.timers.badgersbay` points `OnCalendar =
  "hourly"` at a `Type = "simple"` service that is `wantedBy
  multi-user.target` with `Restart = "on-failure"`. One of the two is wrong, but
  it is not this bug and was not investigated here; it would also mask this fix
  by restarting the service within the hour for unrelated reasons. Tracked
  separately.
- **Reloading instead of restarting.** The server has no signal handler that
  re-reads its files; `reloadTriggers` would need one.
- **Proving the secret exists.** agenix decrypts at activation. The module can
  connect the trigger to the file; it cannot know at evaluation what the file
  will contain, and this change does not pretend otherwise.

## Tracking

- Bean: [elastinix-qxvt](../../../.beans/elastinix-qxvt--badgersbay-does-not-restart-when-its-secrets-chang.md)
