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
"""

import argparse
import json
import os
import sys
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

GITHUB_API = "https://api.github.com/repos/{repo}/security-advisories?per_page=100&sort=published&direction=desc"
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


def fetch_zammad_version(url, token):
    """Ask Zammad for its version: GET /api/v1/version (needs a token with 'admin')."""
    if not url.rstrip("/").endswith("/api/v1/version"):
        url = url.rstrip("/") + "/api/v1/version"  # accept the base URL too
    headers = {"Authorization": f"Token token={token}", "Accept": "application/json"}
    data = json.loads(http_request(url, headers=headers))
    version = data.get("version")
    if not version:
        raise ValueError(f"No 'version' in Zammad response: {str(data)[:200]}")
    return version


def post_slack(webhook_url, text):
    payload = json.dumps({"text": text}).encode()
    http_request(webhook_url, data=payload, headers={"Content-Type": "application/json"})


# --- Version matching -------------------------------------------------------
#
# Zammad advisories use two formats in "vulnerable_version_range":
#   "<= 7.1.2"       standard GitHub range (comma-separated parts are AND-ed)
#   "7.0.2, 7.1.0"   last affected version per release branch:
#                    7.0.x up to 7.0.2 and 7.1.x up to 7.1.0 are affected
#
# Result is always one of AFFECTED / NOT_AFFECTED / UNKNOWN.
# UNKNOWN is alerted like AFFECTED: when in doubt, a human must look.

AFFECTED, NOT_AFFECTED, UNKNOWN = "affected", "not_affected", "unknown"
OPERATORS = ("<=", ">=", "<", ">", "=")


def parse_version(text):
    """'7.1.2' -> (7, 1, 2). Ignores suffixes like '-1'. Raises ValueError if unparseable."""
    core = text.strip().lstrip("v").split("-")[0].split("+")[0]
    parts = tuple(int(p) for p in core.split("."))
    return parts + (0,) * (3 - len(parts))  # '7.1' -> (7, 1, 0)


def matches_constraint(version, constraint):
    for op in OPERATORS:  # longest operators first, so '<=' is not read as '<'
        if constraint.startswith(op):
            other = parse_version(constraint[len(op):])
            return {"<=": version <= other, ">=": version >= other, "<": version < other,
                    ">": version > other, "=": version == other}[op]
    raise ValueError(f"no operator in {constraint!r}")


def check_range(version, vulnerable_range):
    parts = [p.strip() for p in (vulnerable_range or "").split(",") if p.strip()]
    if not parts:
        return UNKNOWN

    with_operator = [p.startswith(OPERATORS) for p in parts]
    try:
        if all(with_operator):
            return AFFECTED if all(matches_constraint(version, p) for p in parts) else NOT_AFFECTED

        if not any(with_operator):
            # Per-branch list: find the entry for our major.minor branch
            branches = {parse_version(p)[:2]: parse_version(p) for p in parts}
            ours = version[:2]
            if ours in branches:
                return AFFECTED if version <= branches[ours] else NOT_AFFECTED
            if ours > max(branches):
                return NOT_AFFECTED  # we run a newer branch than any listed one
            return UNKNOWN           # older/unlisted branch: cannot tell
    except ValueError:
        return UNKNOWN
    return UNKNOWN  # mixed format


def assess(adv, our_version):
    """Return (status, affected_range_text, patched_text) for an advisory."""
    vulns = [v for v in adv.get("vulnerabilities") or []
             if (v.get("package") or {}).get("name", "").lower() in ("zammad", "")]
    ranges = ", ".join(v.get("vulnerable_version_range") or "?" for v in vulns) or "?"
    patched = ", ".join(v.get("patched_versions") or "?" for v in vulns) or "?"

    if our_version is None or not vulns:
        return UNKNOWN, ranges, patched

    results = {check_range(our_version, v.get("vulnerable_version_range")) for v in vulns}
    if AFFECTED in results:
        return AFFECTED, ranges, patched
    if UNKNOWN in results:
        return UNKNOWN, ranges, patched
    return NOT_AFFECTED, ranges, patched


def format_advisory(adv, status, ranges, patched, version_text):
    header = {
        AFFECTED: f":rotating_light: *AFFECTS US* - we run Zammad {version_text}",
        UNKNOWN: f":warning: *Could not determine impact* - we run Zammad {version_text}, please check manually",
        NOT_AFFECTED: f":information_source: Not affected - we run Zammad {version_text}",
    }[status]
    return (
        f"{header}\n"
        "New Zammad security advisory\n"
        f"*{adv.get('summary', 'no summary')}*\n"
        f"ID: {adv.get('ghsa_id')}   CVE: {adv.get('cve_id') or 'n/a'}\n"
        f"Severity: {adv.get('severity') or 'unknown'}\n"
        f"Affected versions: {ranges}   Fixed in: {patched}\n"
        f"Published: {adv.get('published_at')}\n"
        f"{adv.get('html_url')}\n\n"
        + ("Please create a review ticket and plan the upgrade." if status != NOT_AFFECTED
           else "No action needed; recorded in the register.")
    )


def load_seen(path):
    return set(json.loads(path.read_text())) if path.exists() else None


def save_seen(path, seen):
    # Write to a temp file first, then rename: never leaves a half-written file
    tmp = path.with_suffix(".tmp")
    tmp.write_text(json.dumps(sorted(seen), indent=2))
    tmp.replace(path)


def append_register(path, adv, status, our_version, notified):
    entry = {
        "detected_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        **{k: adv.get(k) for k in ("ghsa_id", "cve_id", "severity", "summary", "published_at", "html_url")},
        "our_version": our_version,
        "assessment": status,          # affected / not_affected / unknown
        "notified": notified,          # was a Slack message sent?
    }
    with path.open("a") as f:
        f.write(json.dumps(entry) + "\n")


def run_check(args, webhook):
    state_dir = Path(os.environ.get("STATE_DIRECTORY", args.state_dir))
    seen_file = state_dir / "seen.json"
    register_file = state_dir / "register.jsonl"

    # Which Zammad version do we run? The API (if configured) wins over --zammad-version.
    version_error = None
    if args.zammad_api_url:
        try:
            token = read_credential("zammad-token") or os.environ.get("ZAMMAD_TOKEN")
            if not token:
                raise ValueError("no Zammad token (credential 'zammad-token' or ZAMMAD_TOKEN)")
            args.zammad_version = fetch_zammad_version(args.zammad_api_url, token)
            log(f"Zammad version from API: {args.zammad_version}")
        except Exception as e:
            # Keep going (alerts become 'check manually'), but fail the run at the end
            version_error = e
            args.zammad_version = None
            log(f"ERROR: could not get Zammad version from API: {e}")

    api_url = args.api_url or GITHUB_API.format(repo=args.repository)
    advisories = fetch_advisories(api_url, read_credential("github-token"))
    log(f"Fetched {len(advisories)} advisories for {args.repository}")

    seen = load_seen(seen_file)

    # First run: remember everything that exists, but do not alert on history
    if seen is None:
        save_seen(seen_file, {a["ghsa_id"] for a in advisories})
        post_slack(webhook, f"Zammad advisory monitor initialised on {args.hostname}. "
                            f"Tracking {len(advisories)} existing advisories; new ones will be posted here. "
                            f"Checking against Zammad version: {args.zammad_version or 'not configured (alerting on all)'}.")
        log(f"Initialised state with {len(advisories)} advisories")
        new = []
    else:
        new = [a for a in advisories if a["ghsa_id"] not in seen]
    log(f"New advisories: {len(new)}")

    our_version = None
    if args.zammad_version:
        try:
            our_version = parse_version(args.zammad_version)
        except ValueError:
            log(f"WARNING: cannot parse Zammad version {args.zammad_version!r}; alerting on everything")
    version_text = args.zammad_version or (
        "(version lookup FAILED)" if version_error else "(version not configured)")

    # API returns newest first; handle oldest first so Slack reads chronologically
    for adv in reversed(new):
        status, ranges, patched = assess(adv, our_version)
        notify = status != NOT_AFFECTED or args.notify_unaffected

        if notify:
            post_slack(webhook, format_advisory(adv, status, ranges, patched, version_text))
        # Only mark as seen AFTER a successful post, so failures are retried next run
        seen.add(adv["ghsa_id"])
        save_seen(seen_file, seen)
        # Every advisory is registered, including unaffected ones (ISO evidence)
        append_register(register_file, adv, status, args.zammad_version, notify)
        log(f"ADVISORY ghsa={adv['ghsa_id']} severity={adv.get('severity')} "
            f"assessment={status} notified={notify}")

    if version_error:
        # Non-zero exit -> systemd OnFailure -> "monitor FAILED" message in Slack.
        # No heartbeat ping, so the dead-man's switch also notices.
        raise RuntimeError(f"Zammad version lookup failed: {version_error}")

    if args.heartbeat_url:
        try:
            http_request(args.heartbeat_url)
        except Exception as e:  # a failed heartbeat must not fail the check itself
            log(f"WARNING: heartbeat ping failed: {e}")


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--repository", default="zammad/zammad")
    parser.add_argument("--hostname", default=os.uname().nodename)
    parser.add_argument("--heartbeat-url", default=None)
    parser.add_argument("--zammad-version", default=None,
                        help="Zammad version we run, e.g. 7.1.2. Without it every advisory is alerted.")
    parser.add_argument("--zammad-api-url", default=None,
                        help="Zammad URL, e.g. https://zammad.example.com/api/v1/version; "
                             "token is read from credential 'zammad-token'")
    parser.add_argument("--notify-unaffected", action="store_true",
                        help="Also post advisories that do not affect our version (as info)")
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