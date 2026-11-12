# Vaultwarden Release Monitor

Checks the latest Vaultwarden release on GitHub
(<https://github.com/dani-garcia/vaultwarden/releases>) and posts to Slack when
it is newer than the version we run. Supports ISO 27001 Annex A 8.8
(management of technical vulnerabilities) and A 8.19 (installation of software
on operational systems): we learn about every new release and can plan the
upgrade.

## How it works

The logic is in `modules/nixos/services/iso/vaultwarden-release-monitor.py`
(Python, standard library only). The Nix module only sets up the timer,
secrets and hardening, and runs the script.

1. A systemd timer starts the oneshot service `vaultwarden-release-monitor.service`
   (default: hourly, Monday to Friday, 09:00 to 17:00 Europe/Amsterdam).
2. The service calls `GET /repos/dani-garcia/vaultwarden/releases/latest`, which
   returns the newest published release (never drafts or pre-releases).
3. The release tag is compared with the installed version. That version is read
   automatically from `elastinix.services.vaultwarden.package` when Vaultwarden
   runs on the same host, so it follows the selected `source` (nixpkgs, pinned,
   unstable).
4. If the release is newer than the running version and not yet announced,
   one Slack message is posted with both versions and a link to the release notes.
5. Announced tags are stored in `/var/lib/private/vaultwarden-release-monitor/notified.json`,
   so each release is announced only once.
6. On the first run, one status message is posted: up to date, or update available.
7. If the service fails, `vaultwarden-release-monitor-failure.service` posts a
   warning to Slack.

## Example configuration

On the host that runs Vaultwarden:

```nix
elastinix.services.vaultwarden-release-monitor = {
  enable = true;
  slackWebhookFile = config.age.secrets.zammad-advisory-slack-webhook.path;
};
```

The same Slack webhook as the Zammad advisory monitor can be reused, so both
post to the same channel. For a separate channel, create a second webhook and
agenix secret.

### Version from the Vaultwarden API

Vaultwarden reports its version at `GET /api/version` as a JSON string, for
example `"1.37.5"`. The endpoint is public, so no token is needed:

```nix
elastinix.services.vaultwarden-release-monitor = {
  enable = true;
  slackWebhookFile = config.age.secrets.zammad-advisory-slack-webhook.path;
  versionUrl = "https://vaultwarden.technative.eu/api/version";
};
```

This also works when the monitor runs on another host than Vaultwarden. If
the call fails (Vaultwarden down, network error), new releases are still
announced, with the version shown as "lookup FAILED", and the run is marked
failed, which triggers the failure notification.

## Options

| Option | Type | Default | Description |
|---|---|---|---|
| `enable` | bool | `false` | Enable the monitor |
| `repository` | str | `"dani-garcia/vaultwarden"` | GitHub repository to monitor |
| `installedVersion` | str or null | auto-detected | Version we run; read from `elastinix.services.vaultwarden.package` on the same host, otherwise set by hand. `null` posts every new release |
| `versionUrl` | str or null | `null` | Vaultwarden's public `/api/version` endpoint, queried every run (no token needed); takes precedence over `installedVersion` |
| `schedule` | str | `"Mon..Fri *-*-* 09..17:00:00 Europe/Amsterdam"` | systemd `OnCalendar` expression |
| `slackWebhookFile` | str | — | Path to agenix secret containing the Slack webhook URL |
| `githubTokenFile` | str or null | `null` | Optional GitHub token (avoids the 60 req/h unauthenticated limit) |
| `heartbeatUrl` | str or null | `null` | Optional dead-man's-switch URL pinged after each successful run |

## Operations

```bash
systemctl list-timers vaultwarden-release-monitor.timer   # next / last run
systemctl start vaultwarden-release-monitor.service       # run now
journalctl -u vaultwarden-release-monitor.service         # run history (evidence)
sudo cat /var/lib/private/vaultwarden-release-monitor/notified.json  # announced releases
```

Re-announcing the current status: delete `notified.json` and start the service.

## Upgrading after an announcement

With `source = "pinned"`, update the pinned version with
`pkgs/vaultwarden/update.sh <tag> ./pkgs/vaultwarden` (see the Vaultwarden docs).
With `source = "nixpkgs"`, the new release arrives when nixpkgs packages it.
Remember to raise `minimumVersion` in `service-vaultwarden.nix` after every
production upgrade.

## Limitations

- Only the latest release is checked. If two releases come out between runs,
  only the newest is announced (it includes the older one's changes).
- The monitor only compares version numbers. Read the release notes of every
  announced release to judge how urgent the upgrade is.