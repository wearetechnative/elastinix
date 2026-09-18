## Context

See proposal.md - Why for the symptom and the motivation. What matters for the
approach is where each half of the problem lives.

**The poller.** It was not found by reading badgersbay's units, because it is not
one of them. It is the monitoring stack, and all three pieces are visible in the
`grafana-prometheus` input:

| Where                                       | What it says                                          |
|---------------------------------------------|-------------------------------------------------------|
| `module/prometheus/prometheus.nix`          | `globalConfig.scrape_interval = "30s"`                |
| `module/prometheus/exporters/blackbox.nix`  | `http_2xx`: `method: GET`, `fail_if_not_ssl: true`    |
| `module/prometheus/default.nix`             | `job_name = "blackbox-<customer>"`, targets read from `/etc/prometheus/customers/<customer>/probes/urls.yaml` |

A blackbox target is a URL. A bare `https://badgersbay.<domain>` requests `/`,
and the thirty-second cadence is the global scrape interval, not anything
configured per probe. That explains every line in the bean, including why
nothing turned up in `systemctl list-units` and why the source address is
`127.0.0.1`: the probe arrives at nginx and is proxied to the loopback.

That probes file is `elastinix.services.grafana-prometheus.customers.*.probesFile`
- a path into the host configuration repository. Nothing in this repository sets
it, and the badgersbay module has no business reaching into the monitoring
module to edit it.

**The other half.** `service-badgersbay.nix` declares no health check of any
kind. Evaluating a compute2-shaped configuration at `HEAD` gives
`config.healthchecks.http == { }` and `config.healthchecks.localCommands == { }`.
So there is nothing for a host, a probe or an operator to point at other than
the dashboard, which is the thing that went wrong.

**What is available.** `nixos-healthchecks` is already a flake input, its
`flakeModule` is already imported in `flake.nix`, and its `nixosModules.default`
is imported by both `lib/os_config_live.nix` and `lib/os_config_vm.nix` - so
`healthchecks.*` exists on every elastinix host. `elastinix.programs.e2e-twenty`
already defines `healthchecks.http.twenty` and
`healthchecks.localCommands.twenty_Login` through it.

**What `/health` answers.** It is handled before authentication
(`honeybadger_server.py`, `do_GET`) and returns 200 with:

```json
{
  "status": "ok",
  "service": "honeybadger-server",
  "uptime": { "seconds": 3600, "human_readable": "1h 0m" },
  "statistics": { "total_report_directories": 42, "unique_hosts": 10, ... },
  "storage": { "location": "/data/badgersbay/reports", "accessible": false }
}
```

`accessible` is `storage_path.exists()`. The server does not refuse to serve when
it is false, and the status code stays 200 - which is the whole reason a content
check is needed rather than a code check.

## Goals / Non-Goals

**Goals:**

- The module declares what healthy means for badgersbay, in the repository that
  knows, rather than leaving each host to invent a probe.
- The check fails on a storage location that has gone, which is the failure the
  status code hides.
- The documentation says what a probe must target and why, so the next person
  configuring one does not reach for the dashboard again.

**Non-Goals:**

- **Editing the probes file.** It lives in the host configuration repository.
  This change makes the correct target exist and documents it; pointing the
  probe at it is tracked separately.
- **A periodic on-host health timer.** The docs currently suggest one, and it
  would be the obvious thing to write. It is not written here: the complaint in
  the bean is a poller that produces log lines and no information, and answering
  it by adding a second poller - on every badgersbay host, duplicating what
  prometheus already does every thirty seconds - trades one kind of noise for
  another. `elastinix.services.systemd-monitoring` already turns a `failed`
  badgersbay unit into a log line for hosts that list it.
- **Changing what `/health` reports.** `storage.accessible` being 200 rather
  than 503 is badgersbay's behaviour, in badgersbay's repository. This change
  works with the endpoint as it is.
- **Adding a blackbox module that matches on the body.** `fail_if_body_not_matches_regexp`
  would let the prometheus probe assert `storage.accessible` too. The blackbox
  module list is in the monitoring flake, not here.

## Decisions

### Declare the checks through `nixos-healthchecks`, not as a systemd unit

The framework is already imported on every host, already used by another
elastinix module, and costs nothing at runtime: a definition under
`healthchecks.*` adds no unit, no timer and no process. It is collected into
`healthchecks.rawCommands` and run on demand - `nix run .#healthchecks`, or the
`healthchecks-prometheus` package for line-format output.

| Alternative                                   | Why not                                                                                     |
|-----------------------------------------------|---------------------------------------------------------------------------------------------|
| A oneshot unit plus timer, as the docs suggest | Adds a second poller to answer a complaint about a poller; see Non-Goals                     |
| An option holding a health URL for hosts to use | Hosts do not consume nix values in a YAML probes file; it would be an option nothing reads   |
| Nothing in the module, docs only               | Leaves the repository with no statement of what healthy means, which is how this started      |

The cost is honest and worth stating: these definitions are inert until a flake
that exposes `nixosConfigurations` runs them. The `nixos-healthchecks`
`flakeModule` builds its packages from `self.nixosConfigurations`, and this
repository exposes none - it exports `lib.os_config_live`, which host flakes call.
So `nix run .#healthchecks` here checks nothing, and the checks run from the host
flake. That is already true of `healthchecks.http.twenty`, and it is the reason
the documentation section says where they run rather than only that they exist.

### Two checks, split by what a failure means

- `healthchecks.http.badgersbay` - the server answers. 200 from
  `http://127.0.0.1:<port>/health`, with `honeybadger-server` in the body.
- `healthchecks.localCommands.badgersbay-storage` - what it answers is good.
  Fails on `storage.accessible` being false.

One combined check would report "badgersbay is unhealthy" for two conditions
with entirely different responses: restart the service, versus find out what
happened to the storage directory. The framework prints one title per check, so
splitting them is what makes the output say which.

### The content check is a local command, not `expectedContent`

`healthchecks.http` has an `expectedContent` option, and it is the obvious place
for this. It cannot carry the value. The module interpolates it into generated
Python unescaped:

```python
if "${expectedContent}" not in response_text:
```

The string that matters here is `"accessible": true` - the response is rendered
with `json.dumps(..., indent=2)`, so the quotes are part of it. Substituting it
produces `if ""accessible": true" not in response_text:`, which is a syntax
error, and `pkgs.writers.writePython3` fails the build rather than the check.
Any value containing a double quote has the same problem, so no JSON field can
be asserted this way.

`expectedContent = "honeybadger-server"` is quote-free and is used on the HTTP
check, where it asserts identity: something answered, and it was badgersbay.
The value assertion goes into a `localCommands` script, which parses the JSON
instead of matching a substring - so it reads `storage.accessible` as a boolean
rather than hoping the formatting of the response never changes.

The script is `pkgs.writers.writePython3` with no library list: `urllib.request`
and `json` are in the standard library, so the check pulls in no `requests` and
no `jq`. It prints the storage location it was told about when it fails, because
the next question after "storage is not accessible" is always "which path did it
look at" - and on a host that overrides `configFile`, the module cannot know.

### Address the loopback and the port, not the vhost

The check requests `http://127.0.0.1:<port>/health`, following `cfg.port` as the
firewall rule and the nginx proxy do. Checking `https://badgersbay.<domain>`
would fold nginx, ACME, DNS and the certificate into a badgersbay health check;
those have their own failures and their own probes. This check is about the
service.

### No opt-out option, and no guard on the module being imported

`healthchecks.*` is defined unconditionally inside the existing
`lib.mkIf cfg.enable`, exactly as `e2e-testing.nix` does. The module's
`config.age or null` dance exists because agenix genuinely may be absent;
`nixos-healthchecks` is imported by both entry points in `lib/`, and there is no
elastinix host that has the badgersbay module without it. An `enable` flag for a
check that runs no process and has nothing to disable would be a knob nobody
turns.

## Risks / Trade-offs

- **The 401s continue until the probes file changes.** → This change is
  deliberately half the fix; the other half is one line in another repository and
  is tracked as its own bean. The documentation states the target and the reason
  so the edit is unambiguous.
- **The checks may never be run.** A host flake that does not expose its
  `nixosConfigurations`, or never runs the healthchecks app, gets no value from
  them. → Stated in the docs rather than papered over, and the definitions cost
  nothing where they are not run.
- **`storage.accessible` is `exists()`, not writability.** A directory that
  exists but cannot be written to passes. → Still strictly more than the status
  code detects, and tightening it is badgersbay's side of the line.
- **`expectedContent = "honeybadger-server"` is a weak assertion.** It would
  pass on a response that is otherwise nonsense. → It is the identity half only;
  the storage check does the reading that matters.

## Migration Plan

None. Two definitions are added under `config`; no option is added, renamed or
removed, no unit changes, and no host configuration has to be touched. A deploy
carries the definitions; a rollback removes them and leaves the service exactly
as it is today.
