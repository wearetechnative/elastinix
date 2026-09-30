"""Zammad security advisory monitor (ISO 27001 A.8.8 / A.5.7).

Fetches the GitHub security advisories of a repository, posts every NEW
advisory to a Slack incoming webhook and appends it to an evidence register.

Runs as a systemd oneshot service. Uses only the Python standard library.

Files (inside $STATE_DIRECTORY, provided by systemd):
  seen.json       GHSA ids that were already notified
  register.jsonl  append-only log of detected advisories (ISO evidence)

Secrets (inside $CREDENTIALS_DIRECTORY, provided by systemd LoadCredential):
  slack-webhook   Slack incoming webhook URL
  github-token    optional GitHub token
  heartbeat-url   optional dead-man's-switch URL
"""

import argparse
import json
import os
import sys
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

GITHUB_API = "https://api.github.com/repos/{repo}/security-advisories?state=published&per_page=100&sort=published&direction=desc"
TIMEOUT = 60


def log(message):
    # stdout ends up in the systemd journal: journalctl -u zammad-advisory-monitor
    print(message, flush=True)


def read_credential(name):
    """Return the content of a systemd credential, or None if it does not exist."""
    cred_dir = os.environ.get("CREDENTIALS_DIRECTORY")
    if not cred_dir:
        return None
    path = Path(cred_dir) / name
    return path.read_text().strip() if path.exists() else None


def http_request(url, data=None, headers=None):
    """Small wrapper around urllib. Raises an exception on HTTP errors."""
    request = urllib.request.Request(url, data=data, headers=headers or {})
    with urllib.request.urlopen(request, timeout=TIMEOUT) as response:
        return response.read()


def fetch_advisories(api_url, token=None):
    headers = {
        "Accept": "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28",
        "User-Agent": "elastinix-zammad-advisory-monitor",
    }
    if token:
        headers["Authorization"] = f"Bearer {token}"

    advisories = json.loads(http_request(api_url, headers=headers))
    if not isinstance(advisories, list):
        raise ValueError(f"Unexpected API response: {str(advisories)[:200]}")
    return advisories


def post_slack(webhook_url, text):
    payload = json.dumps({"text": text}).encode()
    http_request(webhook_url, data=payload, headers={"Content-Type": "application/json"})


def format_advisory(adv):
    return (
        "New Zammad security advisory\n"
        f"*{adv.get('summary', 'no summary')}*\n"
        f"ID: {adv.get('ghsa_id')}   CVE: {adv.get('cve_id') or 'n/a'}\n"
        f"Severity: {adv.get('severity') or 'unknown'}\n"
        f"Published: {adv.get('published_at')}\n"
        f"{adv.get('html_url')}\n\n"
        "Please create a review ticket and assess impact."
    )


def load_seen(path):
    return set(json.loads(path.read_text())) if path.exists() else None


def save_seen(path, seen):
    # Write to a temp file first, then rename: never leaves a half-written file
    tmp = path.with_suffix(".tmp")
    tmp.write_text(json.dumps(sorted(seen), indent=2))
    tmp.replace(path)


def append_register(path, adv):
    entry = {
        "detected_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        **{k: adv.get(k) for k in ("ghsa_id", "cve_id", "severity", "summary", "published_at", "html_url")},
    }
    with path.open("a") as f:
        f.write(json.dumps(entry) + "\n")


def ping_heartbeat(url):
    if not url:
        return
    try:
        http_request(url)
    except Exception as e:  # a failed heartbeat must not fail the check itself
        log(f"WARNING: heartbeat ping failed: {e}")


def run_check(args, webhook):
    state_dir = Path(os.environ.get("STATE_DIRECTORY", args.state_dir))
    seen_file = state_dir / "seen.json"
    register_file = state_dir / "register.jsonl"

    heartbeat_url = read_credential("heartbeat-url") or args.heartbeat_url
    api_url = args.api_url or GITHUB_API.format(repo=args.repository)
    advisories = fetch_advisories(api_url, read_credential("github-token"))
    log(f"Fetched {len(advisories)} advisories for {args.repository}")

    seen = load_seen(seen_file)

    # First run: remember everything that exists, but do not alert on history
    if seen is None:
        save_seen(seen_file, {a["ghsa_id"] for a in advisories})
        post_slack(webhook, f"Zammad advisory monitor initialised on {args.hostname}. "
                            f"Tracking {len(advisories)} existing advisories; new ones will be posted here.")
        log(f"Initialised state with {len(advisories)} advisories")
        ping_heartbeat(heartbeat_url)
        return

    new = [a for a in advisories if a["ghsa_id"] not in seen]
    log(f"New advisories: {len(new)}")

    # API returns newest first; notify oldest first so Slack reads chronologically
    for adv in reversed(new):
        post_slack(webhook, format_advisory(adv))
        # Register before marking as seen: a failure in between gives a duplicate
        # register entry on retry rather than a missing one
        append_register(register_file, adv)
        # Only mark as seen AFTER a successful post, so failures are retried next run
        seen.add(adv["ghsa_id"])
        save_seen(seen_file, seen)
        log(f"ADVISORY_NOTIFIED ghsa={adv['ghsa_id']} severity={adv.get('severity')}")

    ping_heartbeat(heartbeat_url)


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--repository", default="zammad/zammad")
    parser.add_argument("--hostname", default=os.uname().nodename)
    parser.add_argument("--heartbeat-url", default=None,
                        help="Fallback when the 'heartbeat-url' credential is not set (local testing)")
    parser.add_argument("--state-dir", default=".", help="Fallback when STATE_DIRECTORY is not set (local testing)")
    parser.add_argument("--api-url", default=None, help="Override the API URL (testing only)")
    parser.add_argument("--notify-failure", action="store_true",
                        help="Only send a 'monitor failed' warning to Slack (used by the OnFailure unit)")
    args = parser.parse_args()

    webhook = read_credential("slack-webhook") or os.environ.get("SLACK_WEBHOOK_URL")
    if not webhook:
        log("ERROR: no Slack webhook (credential 'slack-webhook' or SLACK_WEBHOOK_URL)")
        return 1

    if args.notify_failure:
        post_slack(webhook, f"WARNING: zammad-advisory-monitor FAILED on {args.hostname}. "
                            "Advisories are NOT being monitored. "
                            "Check: journalctl -u zammad-advisory-monitor.service")
        return 0

    run_check(args, webhook)
    return 0


if __name__ == "__main__":
    sys.exit(main())