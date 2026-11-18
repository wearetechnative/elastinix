import argparse
import json
import os
import sys
import urllib.request
from pathlib import Path

GITHUB_LATEST = "https://api.github.com/repos/{repo}/releases/latest"
TIMEOUT = 60

# Health is remembered so a broken run warns once instead of every hour
HEALTH_OK = "ok"
HEALTH_DEGRADED = "degraded"


def log(message):
    print(message, flush=True)


def read_credential(name):
    cred_dir = os.environ.get("CREDENTIALS_DIRECTORY")
    if not cred_dir:
        return None
    path = Path(cred_dir) / name
    return path.read_text().strip() if path.exists() else None


def http_request(url, data=None, headers=None):
    request = urllib.request.Request(url, data=data, headers=headers or {})
    with urllib.request.urlopen(request, timeout=TIMEOUT) as response:
        return response.read()


def post_slack(webhook_url, text):
    payload = json.dumps({"text": text}).encode()
    http_request(webhook_url, data=payload, headers={"Content-Type": "application/json"})


def parse_version(text):
    core = text.strip().lstrip("v").split("-")[0].split("+")[0]
    parts = tuple(int(p) for p in core.split("."))
    return parts + (0,) * (3 - len(parts))


def fetch_latest_release(api_url, token=None):
    headers = {
        "Accept": "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28",
        "User-Agent": "elastinix-vaultwarden-release-monitor",
    }
    if token:
        headers["Authorization"] = f"Bearer {token}"
    release = json.loads(http_request(api_url, headers=headers))
    if not isinstance(release, dict) or not release.get("tag_name"):
        raise ValueError(f"Unexpected API response: {str(release)[:200]}")
    return release


def fetch_running_version(url):
    if not url.rstrip("/").endswith("/api/version"):
        url = url.rstrip("/") + "/api/version"  # accept the base URL too
    log(f"Requesting running version from {url}")
    version = json.loads(http_request(url, headers={"Accept": "application/json"}))
    if not isinstance(version, str) or not version:
        raise ValueError(f"Unexpected response from {url}: {str(version)[:200]}")
    return version


def release_lines(release, installed_text):
    lines = [
        f"*Vaultwarden {release['tag_name']}* released {(release.get('published_at') or '?')[:10]} "
        f"- we run {installed_text}",
    ]
    lines.append(f"Release notes: {release.get('html_url')}")
    return lines


def read_json(path, default):
    if not path.exists():
        return default
    try:
        return json.loads(path.read_text())
    except ValueError:
        log(f"WARNING: ignoring unreadable {path}")
        return default


def write_json(path, value):
    # Write to a temp file first, then rename: never leaves a half-written file
    tmp = path.with_suffix(".tmp")
    tmp.write_text(json.dumps(value, indent=2))
    tmp.replace(path)


def load_notified(path):
    notified = read_json(path, None)
    return notified if isinstance(notified, list) else None


def save_notified(path, tags):
    write_json(path, tags)


def report_health(health_file, webhook, hostname, ok, detail=""):
    """Post only when the health changes: one warning per failure, one recovery."""
    try:
        previous = read_json(health_file, {})
        known = previous.get("health") if isinstance(previous, dict) else None
        state = HEALTH_OK if ok else HEALTH_DEGRADED
        if state == known:
            log(f"Health unchanged: {state}")
            return

        if ok and known is None:
            # Nothing failed yet, so there is nothing to recover from
            write_json(health_file, {"health": state, "detail": detail})
            log(f"Health recorded: {state}")
            return

        if ok:
            text = (
                f"Vaultwarden release monitor is healthy again on {hostname}. "
                "New releases are being posted."
            )
        else:
            text = (
                f"WARNING: vaultwarden-release-monitor FAILED on {hostname}. "
                f"Vaultwarden releases are NOT being monitored: {detail}. "
                "Check: journalctl -u vaultwarden-release-monitor.service"
            )
        try:
            post_slack(webhook, text)
        except Exception as e:
            # Not recording the new state, so the next run tries again
            log(f"WARNING: could not post the health notification: {e}")
            return

        write_json(health_file, {"health": state, "detail": detail})
        log(f"HEALTH_NOTIFIED {state}")
    except Exception as e:
        log(f"WARNING: could not record the health state: {e}")


def run_check(args, webhook):
    state_dir = Path(os.environ.get("STATE_DIRECTORY", args.state_dir))
    state_dir.mkdir(parents=True, exist_ok=True)
    notified_file = state_dir / "notified.json"
    health_file = state_dir / "health.json"

    api_url = args.api_url or GITHUB_LATEST.format(repo=args.repository)
    release = fetch_latest_release(api_url, read_credential("github-token"))
    tag = release["tag_name"]
    log(f"Latest {args.repository} release: {tag}")

    # Which version do we run? The endpoint (if configured) wins over --installed-version.
    version_error = None
    if args.version_url:
        try:
            args.installed_version = fetch_running_version(args.version_url)
            log(f"Running version from API: {args.installed_version}")
        except Exception as e:
            version_error = e
            args.installed_version = None
            log(f"ERROR: could not get running version: {e}")

    installed = None
    if args.installed_version:
        try:
            installed = parse_version(args.installed_version)
        except ValueError:
            log(f"WARNING: cannot parse installed version {args.installed_version!r}")

    installed_text = args.installed_version or "(version not configured)"
    if version_error:
        installed_text = "(version lookup FAILED)"

    try:
        latest = parse_version(tag)
    except ValueError:
        latest = None
        log(f"WARNING: cannot parse release tag {tag!r}; treating it as new")

    # Without the running version we cannot tell whether we are behind, so
    # nothing is announced and no tag is recorded: the release has to be
    # announced by the first run that can read the version again.
    if version_error:
        report_health(
            health_file,
            webhook,
            args.hostname,
            ok=False,
            detail=f"cannot read the running version: {version_error}",
        )
        return 1

    # Up to date only if both versions are known and ours is not older
    up_to_date = installed is not None and latest is not None and latest <= installed
    log(f"Installed: {installed_text}, up to date: {up_to_date}")

    notified = load_notified(notified_file)

    if notified is None:
        # First run: one status message, whatever the state
        if up_to_date:
            text = (
                f"Vaultwarden release monitor initialised on {args.hostname}. "
                f":white_check_mark: We run {installed_text}, which is the latest release ({tag}). "
                "New releases will be posted here."
            )
        elif installed is None:
            text = (
                f"Vaultwarden release monitor initialised on {args.hostname}. "
                f"We do not know which version we run, so there is no comparison yet "
                f"(latest release: {tag}). New releases will be posted here."
            )
        else:
            text = "\n".join(
                [
                    f"Vaultwarden release monitor initialised on {args.hostname}. "
                    ":arrow_up: *Update available.*"
                ]
                + release_lines(release, installed_text)
                + ["New releases will be posted here."]
            )
        post_slack(webhook, text)
        save_notified(notified_file, [tag])
        log("Initialised")

    elif not up_to_date and tag not in notified:
        post_slack(
            webhook,
            "\n".join(
                [":arrow_up: *New Vaultwarden release available*"]
                + release_lines(release, installed_text)
                + ["Please create an upgrade ticket."]
            ),
        )
        # Only remember AFTER a successful post, so failures are retried next run
        save_notified(notified_file, notified + [tag])
        log(f"RELEASE_NOTIFIED tag={tag} installed={installed_text}")

    else:
        log("Nothing to announce")

    report_health(health_file, webhook, args.hostname, ok=True)

    if args.heartbeat_url:
        try:
            http_request(args.heartbeat_url)
        except Exception as e:
            log(f"WARNING: heartbeat ping failed: {e}")


def main():
    parser = argparse.ArgumentParser(description="Vaultwarden release monitor")
    parser.add_argument("--repository", default="dani-garcia/vaultwarden")
    parser.add_argument("--hostname", default=os.uname().nodename)
    parser.add_argument(
        "--installed-version",
        default=None,
        help="Vaultwarden version we run, e.g. 1.37.5. Without it every new release is posted.",
    )
    parser.add_argument(
        "--version-url",
        default=None,
        help="Vaultwarden version endpoint, e.g. https://vaultwarden.example.com/api/version",
    )
    parser.add_argument("--heartbeat-url", default=None)
    parser.add_argument("--state-dir", default=".", help="Fallback when STATE_DIRECTORY is not set (local testing)")
    parser.add_argument("--api-url", default=None, help="Override the API URL (testing only)")
    args = parser.parse_args()

    webhook = read_credential("slack-webhook") or os.environ.get("SLACK_WEBHOOK_URL")
    if not webhook:
        log("ERROR: no Slack webhook (credential 'slack-webhook' or SLACK_WEBHOOK_URL)")
        return 1

    try:
        return run_check(args, webhook)
    except Exception as e:
        # A crashed run is a monitoring gap too: report it once, not every hour
        log(f"ERROR: {e}")
        state_dir = Path(os.environ.get("STATE_DIRECTORY", args.state_dir))
        state_dir.mkdir(parents=True, exist_ok=True)
        report_health(
            state_dir / "health.json",
            webhook,
            args.hostname,
            ok=False,
            detail=str(e)[:200],
        )
        return 1


if __name__ == "__main__":
    sys.exit(main())
