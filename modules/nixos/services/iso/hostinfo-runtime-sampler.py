import argparse
import json
import os
import pwd
import re
import subprocess
import tempfile
from datetime import datetime, timezone

DAILY_DIR = None
HASP = None
HASP_AWS = None
INTERVAL_SECONDS = None
GAP_INTERVALS = None
SCHEMA_VERSION = 2
OBSERVE_SOCKETS = False
SS = "ss"

# /nix/store/<32 chars>-<name>, capturing only <name> and stopping at the first
# path separator, so a mapped library resolves to the package name that owns it.
# The hash is deliberately excluded: consumers join this against vulnix output,
# which is keyed by package name. Two builds of the same name therefore merge,
# and if either is in use the name counts as in use -- the conservative
# direction.
STORE = re.compile(r"/nix/store/[a-z0-9]{32}-([^/\s\x00\"';]+)")
PID_RE = re.compile(r"pid=(\d+)")

WILDCARD_ADDRS = {"0.0.0.0", "::", "*"}


def read(path):
    try:
        with open(path, "rb") as fh:
            return fh.read().decode("utf-8", "replace")
    except (OSError, ValueError):
        return ""


def unit_of(pid):
    for line in read(f"/proc/{pid}/cgroup").splitlines():
        m = re.search(r"([^/]+\.service)", line)
        if m:
            return m.group(1)
    return None


def user_of(pid):
    for line in read(f"/proc/{pid}/status").splitlines():
        if line.startswith("Uid:"):
            try:
                uid = int(line.split()[1])
            except (IndexError, ValueError):
                return None
            try:
                return pwd.getpwuid(uid).pw_name
            except KeyError:
                return str(uid)
    return None


def normalize_addr(addr):
    """Strip the scope suffix and unwrap IPv4-mapped IPv6.

    ss reports both "127.0.0.53%lo" and "::ffff:127.0.0.1". The second is an
    IPv4-mapped IPv6 address for a loopback listener; classifying it as
    "specific" would cost us the strongest claim available -- that nothing off
    this machine can reach it at all.
    """
    addr = addr.split("%", 1)[0]
    if addr.lower().startswith("::ffff:"):
        addr = addr[len("::ffff:"):]
    return addr


def ephemeral_range():
    """The kernel's own client port range. Read, never assumed."""
    text = read("/proc/sys/net/ipv4/ip_local_port_range").split()
    try:
        return int(text[0]), int(text[1])
    except (IndexError, ValueError):
        return 32768, 60999


def is_client_port(proto, port, low, high):
    """An outbound UDP conversation is not a listening service.

    ss reports UDP sockets with no state, so a socket timesyncd bound to
    receive one NTP reply looks identical to a service. Left unclassified,
    each sample adds a new phantom listener and the cumulative set grows
    without bound. TCP is exempt: LISTEN state is unambiguous.
    """
    return proto == "udp" and low <= port <= high


def bind_class(addr):
    """loopback / wildcard / specific.

    The IPv6 wildcard counts as wildcard, not as an IPv6-only bind: such a
    socket accepts IPv4 connections too unless v6only is set, so calling it
    anything else would understate reachability.
    """
    plain = normalize_addr(addr)
    if plain in WILDCARD_ADDRS:
        return "wildcard"
    if plain.startswith("127.") or plain == "::1":
        return "loopback"
    return "specific"


def split_hostport(text):
    if text.startswith("["):
        host, _, port = text.rpartition("]:")
        return host[1:], port
    host, _, port = text.rpartition(":")
    return host, port


def sample_processes():
    """Package name -> units observed holding it, and unit -> users."""
    packages = {}
    unit_users = {}
    for pid in os.listdir("/proc"):
        if not pid.isdigit():
            continue
        blob = read(f"/proc/{pid}/maps")
        try:
            blob += "\n" + os.path.realpath(f"/proc/{pid}/exe")
        except OSError:
            pass
        blob += "\n" + read(f"/proc/{pid}/cmdline").replace("\0", "\n")
        names = set(STORE.findall(blob))
        unit = unit_of(pid)
        if unit:
            user = user_of(pid)
            if user:
                unit_users.setdefault(unit, set()).add(user)
        for name in names:
            entry = packages.setdefault(name, set())
            if unit:
                entry.add(unit)
    return packages, unit_users


def sample_sockets():
    """Listening sockets, keeping the raw address beside its class."""
    # ss queries sock_diag over netlink. If the unit denied AF_NETLINK this
    # would yield nothing while still exiting successfully -- the same
    # silent-blindness failure as hiding /proc -- so failure must be loud.
    out = subprocess.run(
        [SS, "-lntupH"], check=True, capture_output=True, text=True
    ).stdout
    low, high = ephemeral_range()
    sockets = []
    clients = 0
    for line in out.splitlines():
        fields = line.split()
        if len(fields) < 5:
            continue
        proto = fields[0]
        if proto not in ("tcp", "udp"):
            continue
        addr, port = split_hostport(fields[4])
        if not port.isdigit():
            continue
        unit = None
        user = None
        for pid in PID_RE.findall(line):
            unit = unit or unit_of(pid)
            user = user or user_of(pid)
        if is_client_port(proto, int(port), low, high):
            clients += 1
            continue
        sockets.append({
            "port": int(port),
            "proto": proto,
            "address": addr,
            "bindClass": bind_class(addr),
            "unit": unit,
            "user": user,
        })
    return sockets, clients


def uptime_seconds():
    """How long this boot has been running, or None when unreadable."""
    try:
        with open("/proc/uptime") as fh:
            return float(fh.read().split()[0])
    except (OSError, ValueError, IndexError):
        return None


def account_gap(previous, now):
    """(observed, unobserved, downtime) seconds this sample accounts for.

    A gap longer than one sample means a sample that should have been taken was
    not. Whether that is the host's fault or the sampler's is decided by uptime:
    shorter than the gap means the machine rebooted, so the missing time is
    downtime and no observation was owed. Longer means the machine was running
    while nothing sampled it, which is the only failure this can detect and the
    one it must not hide.
    """
    if not previous:
        return INTERVAL_SECONDS, 0, 0
    try:
        gap = (datetime.strptime(now, "%Y-%m-%dT%H:%M:%SZ")
               - datetime.strptime(previous, "%Y-%m-%dT%H:%M:%SZ")).total_seconds()
    except ValueError:
        return INTERVAL_SECONDS, 0, 0
    if gap <= 0:
        return 0, 0, 0
    if gap <= INTERVAL_SECONDS * GAP_INTERVALS:
        return int(gap), 0, 0
    missing = int(gap) - INTERVAL_SECONDS
    up = uptime_seconds()
    if up is not None and up < gap:
        return INTERVAL_SECONDS, 0, missing
    return INTERVAL_SECONDS, missing, 0


def record_path(date):
    return os.path.join(DAILY_DIR, date + ".json")


def seal_previous(today):
    """Mark every record older than today as sealed, once.

    Sealing is otherwise implicit -- a record is only ever written to on its own
    day, because its filename is the date. The flag exists so a consumer can tell
    a finished day from the one in progress without consulting a clock.
    """
    try:
        names = os.listdir(DAILY_DIR)
    except OSError:
        return
    for name in names:
        if not name.endswith(".json") or name == "index.json":
            continue
        date = name[:-len(".json")]
        if date >= today:
            continue
        path = os.path.join(DAILY_DIR, name)
        try:
            with open(path) as fh:
                doc = json.load(fh)
        except (OSError, ValueError):
            continue
        if doc.get("sealed"):
            continue
        doc["sealed"] = True
        doc["complete"] = doc.get("unobservedSeconds", 0) == 0
        write_json(path, doc)


def load_record(now, today):
    """Today's record, started fresh when the day has rolled over."""
    try:
        with open(record_path(today)) as fh:
            doc = json.load(fh)
    except (OSError, ValueError):
        doc = {}
    doc["schemaVersion"] = SCHEMA_VERSION
    doc["date"] = today
    doc["intervalSeconds"] = INTERVAL_SECONDS
    doc["sealed"] = False
    doc.setdefault("firstSample", now)
    doc.setdefault("sampleCount", 0)
    doc.setdefault("observedSeconds", 0)
    doc.setdefault("unobservedSeconds", 0)
    doc.setdefault("downtimeSeconds", 0)
    doc.setdefault("inuse", {}).setdefault("observed", {})
    sockets = doc.setdefault("sockets", {})
    sockets.setdefault("observed", {})
    sockets.setdefault("current", [])
    doc.setdefault("units", {}).setdefault("user", {})
    return doc


def write_index(today):
    """Which days exist and which one is still open.

    The hostinfo server is a static file server and its directory listing is
    HTML, so a consumer would have to scrape it. An index answers the only
    question a consumer has -- which sealed days can I fetch -- in one request,
    and it is an index rather than evidence, so it may be rewritten freely.
    """
    try:
        names = sorted(n[:-len(".json")] for n in os.listdir(DAILY_DIR)
                       if n.endswith(".json") and n != "index.json")
    except OSError:
        names = []
    write_json(os.path.join(DAILY_DIR, "index.json"), {
        "schemaVersion": SCHEMA_VERSION,
        "sealed": [d for d in names if d < today],
        "current": today,
    })


def read_json(path):
    try:
        with open(path) as fh:
            doc = json.load(fh)
        return doc if isinstance(doc, dict) else None
    except (OSError, ValueError):
        return None


def write_json(path, payload):
    # atomic replace: a crash mid-write must not destroy accumulated history
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path), suffix=".tmp")
    try:
        with os.fdopen(fd, "w") as fh:
            json.dump(payload, fh, indent=1, sort_keys=True)
        # mkstemp creates 0600 and os.replace preserves it, which would leave
        # the document unreadable by the hostinfo HTTP server (it runs as
        # nobody) and serve a 404 despite the file existing.
        os.chmod(tmp, 0o644)
        os.replace(tmp, path)
    except BaseException:
        os.unlink(tmp)
        raise


# The accumulating documents this replaced. tmpfiles no longer creates the
# symlinks, but it does not remove them either -- its remove pass runs only at
# boot, so on a host with weeks of uptime the hostinfo server would keep
# serving a frozen inuse.json with a plausible lastSample and a sample count
# that never moves again. Removed here so it happens within one interval.
LEGACY_ABSOLUTE = [
    "/var/lib/inuse-sampler/inuse.json",
    "/var/lib/inuse-sampler/runtime-facts.json",
]
LEGACY_SERVED = ["inuse.json", "runtime-facts.json"]
LEGACY = []
# Where the daily records used to live, before state moved into the served
# directory. Not removed and not migrated -- only reported, because silently
# relocating evidence is worse than a loud complaint.
MOVED_FROM = "/var/lib/inuse-sampler/daily"


def drop_legacy():
    for path in LEGACY:
        try:
            os.remove(path)
            print(f"removed stale {path}")
        except FileNotFoundError:
            pass
        except OSError as e:
            print(f"could not remove {path}: {e}")


def warn_unmoved():
    """Complain if observation is not actually stored where it is served.

    Two distinct mistakes, both silent and both costly:

    A stale symlink. Observation used to live at MOVED_FROM and be symlinked
    into the served directory. tmpfiles will not replace a symlink with a
    directory and its remove pass runs only at boot, so on a host with weeks
    of uptime the records keep living at the old path -- where an ordinary
    cleanup deletes them and the symlink is left dangling.

    Records left behind. If the symlink is gone but the old directory still
    holds records, the series has started over, which puts inuse="unknown" on
    every finding until a day seals again.
    """
    if os.path.islink(DAILY_DIR):
        print(f"WARNING: {DAILY_DIR} is still a symlink to "
              f"{os.path.realpath(DAILY_DIR)}. Records are not stored where "
              "they are served, so deleting the old directory destroys them. "
              f"Replace the symlink with a real directory and move the records "
              "into it.")
        return
    try:
        # index.json is regenerated every run, so it is not evidence and
        # must not keep the warning alive after the records have been moved.
        left = [n for n in os.listdir(MOVED_FROM)
                if n.endswith(".json") and n != "index.json"]
    except OSError:
        return
    if not left or os.path.realpath(MOVED_FROM) == os.path.realpath(DAILY_DIR):
        return
    print(f"WARNING: {len(left)} record(s) still in {MOVED_FROM}; observation "
          f"now lives in {DAILY_DIR}. Move them, or the period a negative claim "
          "rests on starts over.")


def main():
    global DAILY_DIR, HASP, HASP_AWS, INTERVAL_SECONDS, GAP_INTERVALS
    global OBSERVE_SOCKETS, SS, LEGACY

    parser = argparse.ArgumentParser()
    parser.add_argument("--hostinfo-dir", required=True)
    parser.add_argument("--interval-seconds", type=int, required=True)
    parser.add_argument("--gap-intervals", type=int, required=True)
    parser.add_argument("--observe-sockets", type=int, default=0)
    parser.add_argument("--ss", default="ss")
    args = parser.parse_args()

    DAILY_DIR = os.path.join(args.hostinfo_dir, "observations")
    HASP = os.path.join(args.hostinfo_dir, "hasp.json")
    HASP_AWS = os.path.join(args.hostinfo_dir, "hasp-aws.json")
    INTERVAL_SECONDS = args.interval_seconds
    GAP_INTERVALS = args.gap_intervals
    OBSERVE_SOCKETS = bool(args.observe_sockets)
    SS = args.ss
    LEGACY = LEGACY_ABSOLUTE + [
        os.path.join(args.hostinfo_dir, name) for name in LEGACY_SERVED
    ]

    stamp = datetime.now(timezone.utc)
    now = stamp.strftime("%Y-%m-%dT%H:%M:%SZ")
    today = stamp.strftime("%Y-%m-%d")

    os.makedirs(DAILY_DIR, exist_ok=True)
    drop_legacy()
    warn_unmoved()
    seal_previous(today)
    doc = load_record(now, today)

    # Accounted before lastSample is advanced, so the gap is measured against
    # the previous sample rather than against this one.
    observed, unobserved, downtime = account_gap(doc.get("lastSample"), now)
    doc["observedSeconds"] = int(doc["observedSeconds"]) + observed
    doc["unobservedSeconds"] = int(doc["unobservedSeconds"]) + unobserved
    doc["downtimeSeconds"] = int(doc["downtimeSeconds"]) + downtime
    doc["lastSample"] = now
    doc["sampleCount"] = int(doc["sampleCount"]) + 1
    # Strict: any time the host was running and nothing sampled it leaves the day
    # incomplete. Downtime does not, because no observation was owed.
    doc["complete"] = doc["unobservedSeconds"] == 0

    packages, unit_users = sample_processes()

    observed_pkgs = doc["inuse"]["observed"]
    for name, units in packages.items():
        entry = observed_pkgs.setdefault(name, {})
        entry["samples"] = int(entry.get("samples", 0)) + 1
        entry["lastSeen"] = now
        entry["units"] = sorted(set(entry.get("units", [])) | units)

    users_map = doc["units"]["user"]
    for unit, users in unit_users.items():
        users_map[unit] = sorted(set(users_map.get(unit, [])) | users)

    sockets = []
    if OBSERVE_SOCKETS:
        sockets, clients = sample_sockets()
        low, high = ephemeral_range()
        doc["sockets"]["clientPortRange"] = [low, high]
        doc["sockets"]["clientSocketsLastSample"] = clients
        sock_observed = doc["sockets"]["observed"]
        # One increment per sample, not per socket: a listener bound on both
        # 0.0.0.0 and :: is two sockets under one key, and counting each would
        # report more samples than were ever taken.
        counted = set()
        for sock in sockets:
            key = "%d/%s/%s" % (sock["port"], sock["proto"], sock["bindClass"])
            entry = sock_observed.setdefault(key, {})
            if key not in counted:
                entry["samples"] = int(entry.get("samples", 0)) + 1
                counted.add(key)
            entry["lastSeen"] = now
            entry["addresses"] = sorted(
                set(entry.get("addresses", [])) | {sock["address"]})
            entry["units"] = sorted(
                set(entry.get("units", []))
                | ({sock["unit"]} if sock["unit"] else set()))
            entry["users"] = sorted(
                set(entry.get("users", []))
                | ({sock["user"]} if sock["user"] else set()))
        # Point-in-time, replaced each run. Negative claims must use the set
        # above, unioned across the days of the period: a listener bound briefly
        # under load would be absent here, and granting unreachability on that
        # basis is exactly the silent wrongness this document exists to avoid.
        doc["sockets"]["current"] = sorted(
            sockets, key=lambda s: (s["port"], s["proto"], s["address"]))

    # The facts that were in force today, named rather than recomputed. hasp.json
    # is a pure build product and its hash is the invalidation signal, so it is
    # carried through untouched.
    hasp = read_json(HASP)
    doc["haspHash"] = hasp.get("haspHash") if hasp else None
    aws = read_json(HASP_AWS)
    if aws:
        changed = sorted(set(doc.get("awsChangedKeys") or [])
                         | set(aws.get("changedKeys") or []))
        doc["aws"] = {
            "tier": aws.get("tier"),
            "lastCollected": aws.get("lastCollected"),
            "facts": aws.get("facts") or {},
        }
        doc["awsChangedKeys"] = changed
    else:
        doc.setdefault("aws", None)
        doc.setdefault("awsChangedKeys", [])

    write_json(record_path(today), doc)
    write_index(today)

    print(
        "%s sample %d: %d packages in use, %d observed today, %d sockets, "
        "%d units, observed %.1f h, unobserved %d s, downtime %d s, %s"
        % (today, doc["sampleCount"], len(packages), len(observed_pkgs),
           len(sockets), len(users_map), doc["observedSeconds"] / 3600.0,
           doc["unobservedSeconds"], doc["downtimeSeconds"],
           "complete" if doc["complete"] else "INCOMPLETE"))


if __name__ == "__main__":
    main()
