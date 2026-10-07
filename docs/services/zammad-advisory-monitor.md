# Zammad Advisory Monitor

Monitors the GitHub security advisories of Zammad
(<https://github.com/zammad/zammad/security/advisories>) and posts every new
advisory to a Slack channel. Supports ISO 27001 Annex A 8.8 (management of
technical vulnerabilities) and A 5.7 (threat intelligence).

Since ZAA-2026-07 (April 2026) Zammad publishes advisories on GitHub only, so
GitHub is the primary source.

## How it works

The logic is in `modules/nixos/services/iso/zammad-advisory-monitor.py`
(Python, standard library only). The Nix module only sets up the timer,
secrets and hardening, and runs the script.


1. A systemd timer (`zammad-advisory-monitor.timer`, hourly by default) starts
   the oneshot service `zammad-advisory-monitor.service`.
2. The service calls the public GitHub API
   `GET /repos/zammad/zammad/security-advisories`.
3. Advisory IDs (GHSA) are compared with `/var/lib/zammad-advisory-monitor/seen.json`.
4. Each new advisory is posted to Slack and appended to
   `/var/lib/zammad-advisory-monitor/register.jsonl` (evidence register).
5. On the very first run (no `seen.json`) every existing advisory is assessed
   against the Zammad version and ONE baseline summary is posted, listing the
   advisories that affect (or may affect) the running version, sorted by
   severity, with the version that fixes all of them. Every existing advisory
   is written to the register with `"source": "baseline"`.
6. If the service fails, `zammad-advisory-monitor-failure.service` posts a
   warning to Slack.
7. Optionally, a heartbeat URL is pinged after every successful run, so an
   external service alerts when the host or timer stops entirely.

## Version filtering

Each advisory's `vulnerable_version_range` is compared with `zammadVersion`:

- **affected**: posted as "AFFECTS US", with the fixed version.
- **unknown** (range can't be parsed, older unlisted branch, no version set):
  posted with a "check manually" warning. When in doubt, a human looks.
- **not affected**: not posted (unless `notifyUnaffected = true`), but always
  written to `register.jsonl` with `"assessment": "not_affected"`, so every
  advisory and its automatic assessment remain auditable.

Both range formats Zammad uses are supported: standard ranges (`<= 7.1.2`,
`>= 7.0.0, < 7.1.3`) and per-branch lists (`7.0.2, 7.1.0` meaning 7.0.x up to
7.0.2 and 7.1.x up to 7.1.0).

When the monitor runs on a different host than Zammad, set `zammadVersion` by
hand and update it with every Zammad upgrade; a stale value silently hides
alerts. Running on the Zammad host avoids that, because the version comes
from the deployed package.

### Version from the Zammad API

With `zammadApiUrl` set, the monitor calls `GET /api/v1/version` on every run
with the token from `zammadTokenFile`. The endpoint requires a token with the
`admin` permission (Zammad: Profile -> Token Access), so store it in agenix,
give it an expiry date and rotate it before it expires.

If the call fails (expired token, Zammad down, TLS error), new advisories are
posted as "could not determine impact" and the run is marked failed, which
triggers the failure notification. Monitoring never silently stops filtering
into nothing.

```nix
age.secrets.zammad-version-token.file = ./secrets/zammad-version-token.age;

elastinix.services.zammad-advisory-monitor = {
  enable = true;
  slackWebhookFile = config.age.secrets.zammad-advisory-slack-webhook.path;
  zammadApiUrl = "https://zammad.example.com/api/v1/version";
  zammadTokenFile = config.age.secrets.zammad-version-token.path;
};
```

## Example configuration

```nix
age.secrets.zammad-advisory-slack-webhook = {
  file = ./secrets/zammad-advisory-slack-webhook.age;
};

elastinix.services.zammad-advisory-monitor = {
  enable = true;
  slackWebhookFile = config.age.secrets.zammad-advisory-slack-webhook.path;
  # heartbeatUrl = "https://hc-ping.com/<uuid>";   # recommended
};
```

## Options

| Option | Type | Default | Description |
|---|---|---|---|
| `enable` | bool | `false` | Enable the monitor |
| `repository` | str | `"zammad/zammad"` | GitHub repository to monitor |
| `schedule` | str | `"hourly"` | systemd `OnCalendar` expression |
| `slackWebhookFile` | str | — | Path to agenix secret containing the Slack webhook URL |
| `githubTokenFile` | str or null | `null` | Optional GitHub token (avoids the 60 req/h unauthenticated limit) |
| `zammadVersion` | str or null | auto-detected | Version to check against; read from `elastinix.services.zammad.package` when Zammad runs on the same host, otherwise set by hand. `null` alerts on everything |
| `zammadApiUrl` | str or null | `null` | Zammad version endpoint (`https://<zammad>/api/v1/version`), queried every run; takes precedence over `zammadVersion` |
| `zammadTokenFile` | str or null | `null` | agenix secret with a Zammad API token (`admin` permission); required with `zammadApiUrl` |
| `notifyUnaffected` | bool | `false` | Also post advisories that do not affect our version (as info) |
| `heartbeatUrl` | str or null | `null` | Optional dead-man's-switch URL pinged after each successful run |

## Age secret format

The file contains only the webhook URL:

```
https://hooks.slack.com/services/T000/B000/XXXXXXXX
```

```bash
agenix -e secrets/zammad-advisory-slack-webhook.age
```

Secrets are passed with systemd `LoadCredential`, so the service runs as an
unprivileged `DynamicUser` while the secret file stays owned by root.

## Operations

```bash
systemctl list-timers zammad-advisory-monitor.timer   # next / last run
systemctl start zammad-advisory-monitor.service       # run now
journalctl -u zammad-advisory-monitor.service         # run history (evidence)
cat /var/lib/private/zammad-advisory-monitor/register.jsonl  # detected advisories
```

Testing a notification: remove one ID from `seen.json` and start the service.

Re-running the baseline (e.g. after an upgrade, or for the quarterly compliance
check): delete `seen.json` and start the service. It posts a fresh baseline
summary for the current version; earlier register entries are kept.

## Local testing (without NixOS)

```bash
SLACK_WEBHOOK_URL=https://hooks.slack.com/services/... \
  python3 modules/nixos/services/iso/zammad-advisory-monitor.py --state-dir /tmp/zam
```

The first run initialises `/tmp/zam/seen.json`. Delete an ID from it and run
again to see a real notification.

## ISO 27001 evidence

- Configuration and change history: this module and the host configuration in git.
- Monitoring ran: `journalctl -u zammad-advisory-monitor.service` and heartbeat history.
- Advisories detected and when: `register.jsonl`.
- Assessment and decisions: the review ticket created for each advisory
  (outside this module).

## Limitations

- Only the first 100 advisories (newest first) are fetched. That is enough to
  catch new advisories.
- The service does not assess impact. Each advisory still needs a human review.