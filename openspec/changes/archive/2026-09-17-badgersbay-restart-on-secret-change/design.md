## Context

`modules/nixos/services/service-badgersbay.nix` starts the server from a
`script` that interpolates four paths:

    honeybadger-server \
      --config ${cfg.configFile} \
      --token-file ${cfg.tokenFile} \
      --dashboard-password-file ${cfg.dashboardPasswordFile} \
      --asset-register ${cfg.assetRegisterFile}

The server reads each one at startup and never again. Whether a deploy reaches
the running process therefore depends entirely on whether those interpolated
strings change:

```
                         path in the unit        content changes →
                                                 unit changes?
  generated config       /nix/store/abc…-…yaml   yes  (store path ≡ content)
  host configFile        /run/agenix/…-config    no
  tokenFile              /run/agenix/…-tokens    no
  dashboardPasswordFile  /run/agenix/…-password  no
  assetRegisterFile      /run/agenix/…-assets    no
```

Four of the five are invisible to systemd. The module has no `restartTriggers`,
so nothing else compensates. Verified by evaluating the module as compute2
configures it: `systemd.services.badgersbay.restartTriggers` is `[ ]`.

## Goals / Non-Goals

**Goals**

- A change to any of the four files restarts the service.
- The restart happens after the new content is on disk.
- The mechanism works for a path that is stable by design.

**Non-Goals**

- Reloading in place. The server has no handler that re-reads its files.
- Watching the files at runtime (`systemd.paths`, an inotify sidecar). The
  question "did this deploy take effect" is a deploy-time question, and
  `switch-to-configuration` already answers it for everything else.
- The hourly timer pointed at this long-running service. Wrong, unrelated, and
  it would mask this fix by restarting the service within the hour anyway.

## Decisions

### Trigger on the encrypted source, not on the decrypted file

The obvious trigger - the file's content - cannot be read. agenix decrypts at
activation on the target host; at evaluation there is nothing at
`/run/agenix/badgersbay-tokens`, and on a build host that path would be a
different machine's secret if it existed at all. Reading it would also drag a
secret into the world-readable store, which the module's own assertions exist to
prevent.

What does change with the content is the ciphertext. `age.secrets.<name>.file`
is the `.age` file, a store path, already public, and it changes whenever
someone runs `agenix -e` on that secret. The module already has the lookup it
needs - `declaredSecret`, which finds the `age.secrets` entry whose `path`
matches a given value, written for the assertions.

So each file contributes:

```
  trigger(file) = [ its path ]                       always
               ++ [ the .age source ]                when agenix declares it
```

The path is kept in the list even though it is redundant for an agenix secret
and already present in the script for a store path. It costs nothing, and it
makes the list say what it is about: these four files.

| Alternative                            | Why not                          |
|----------------------------------------|----------------------------------|
| Hash the decrypted file at eval time   | Not readable; would leak         |
| `passAsFile` / read `age.secrets.file` | Ciphertext hash ≡ the store path |
| `restartIfChanged` on a `systemd.path` | Runtime watch for a deploy-time  |
|                                        | question; needs its own unit     |
| Always restart on every deploy         | Loud, and hides what changed     |

### Accept a restart on re-encryption

age encryption is non-deterministic: re-encrypting the same plaintext yields
different ciphertext, hence a different store path, hence a restart. Adding a
host key to a secret therefore restarts badgersbay even though its content is
unchanged.

Taken deliberately. The failure being fixed is silent and open-ended - a token
that is wrong for as long as nobody restarts the service. The cost of the
over-restart is bounded and visible: a few seconds during a deploy that was
already restarting things.

### Restart, not reload, and the ordering that makes it safe

`switch-to-configuration` stops the units it has to restart, runs the activation
scripts, and only then starts them. agenix installs its secrets from
`system.activationScripts.agenixInstall` (with `agenixChown` after `users`), so
the decrypted file is in place before the restarted unit's first read.

That ordering holds for the activation-script path, which is the one these hosts
take. A host that enables `systemd.sysusers` gets agenix as
`agenix-install-secrets.service` at `sysinit.target` instead, and this module
declares no ordering against that unit. No elastinix host enables it - verified
by evaluation - and inventing an `after` for a unit that does not exist on any
of them would be worse than recording the limit here.

### Include `configFile`

`configFile` is not a secret and is not in the module's `secretFiles` list, but
it is the file that caused the incident: compute2 delivers it through agenix, so
it has exactly the stable-path problem. The trigger list is built from "every
file the server reads at startup", which is `configFile` plus `secretFiles`, and
is not the same list as "every secret", which is what the assertions iterate.

## Risks / Trade-offs

- **A restart is a restart.** Submissions in flight during the deploy fail and
  the host retries on its next run; the dashboard is briefly unavailable. Both
  already happen on any closure change that touches the unit.
- **A bad register now takes the service down at deploy time** rather than at
  the next unrelated restart. That is the server's existing refusal reaching the
  moment it belongs to - the deploy that introduced the bad register - and it is
  visible in the unit state rather than silent.
- **A hand-placed secret file is still invisible.** Nothing evaluable tracks it.
  Documented rather than papered over.

## Verification

The module has no in-tree test harness, and the repository has none for any
service module. Verified by evaluating the module out of tree against the real
flake inputs, as two hosts:

1. compute2-shaped - all four files agenix secrets at `/run/agenix` paths - and
   asserting the resulting `restartTriggers` contains each path and each `.age`
   source, and that editing one secret changes the list.
2. Default-shaped - generated `configFile`, no register - and asserting the list
   covers what is set and says nothing about what is not.

The harness lives outside the repository; committing a test framework for one
module is a larger change than this fix.
