"""Normalize one central scan run into a single evidence bundle.

Finding semantics mirror the Prometheus exporter deliberately: severity
mapping, output grouping, vendor exclusion and the in-use liveness guards are
identical, so a report built from this bundle cannot contradict the dashboards.
Change both or neither.
"""

import argparse
import hashlib
import json
import os
import sys
import tempfile
from datetime import datetime, timedelta, timezone

SCHEMA_VERSION = 1
STAMP = "%Y-%m-%dT%H:%M:%SZ"

ARTIFACTS = (
    "packages.json",
    "hasp.json",
    "hasp-aws.json",
    "docker-images.json",
)

OUTPUT_SUFFIXES = (
    "-bin", "-dev", "-doc", "-man", "-lib",
    "-getent", "-xxd", "-info", "-devdoc", "-out", "-env",
)

CVSS_SEVERITY = [
    (9.0, "CRITICAL"),
    (7.0, "HIGH"),
    (4.0, "MEDIUM"),
    (0.0, "LOW"),
]

warnings = []


def warn(message):
    warnings.append(message)
    print("WARNING: " + message, file=sys.stderr)


def now_stamp():
    return datetime.now(timezone.utc).strftime(STAMP)


def parse_stamp(text):
    return datetime.strptime(text, STAMP).replace(tzinfo=timezone.utc)


def cvss_to_severity(score):
    if score is None:
        return "UNKNOWN"
    for threshold, label in CVSS_SEVERITY:
        if score >= threshold:
            return label
    return "LOW"


def group_key(name, dedup):
    if not dedup:
        return name
    changed = True
    while changed:
        changed = False
        for suffix in OUTPUT_SUFFIXES:
            if name.endswith(suffix):
                name = name[:-len(suffix)]
                changed = True
    return name


def vendor_excluded(pname, vendors, exclusions):
    disowned = exclusions.get(pname)
    if not disowned or not vendors:
        return False
    return all(vendor in disowned for vendor in vendors)


def load_json(path):
    try:
        with open(path) as fh:
            return json.load(fh)
    except (OSError, ValueError) as exc:
        warn("%s unusable (%s)" % (path, exc))
        return None


def host_doc(host_dir, name):
    """A host's document as a dict, or None."""
    doc = load_json(os.path.join(host_dir, name))
    return doc if isinstance(doc, dict) else None


def read_state(path):
    """host -> artifact -> outcome record, from the fetch loop's JSONL."""
    state = {}
    try:
        with open(path) as fh:
            lines = fh.read().splitlines()
    except OSError as exc:
        warn("fetch state %s unreadable (%s); coverage will be empty" % (path, exc))
        return state
    for line in lines:
        line = line.strip()
        if not line:
            continue
        try:
            record = json.loads(line)
        except ValueError:
            warn("unparseable fetch state line, ignored")
            continue
        host = record.get("host")
        artifact = record.get("artifact")
        if not host or not artifact:
            continue
        state.setdefault(host, {})[artifact] = record
    return state


def skip_reason(record):
    if record is None:
        return "no fetch attempted"
    status = record.get("status")
    if status == "missing":
        return "hostinfo unreachable or artifact absent (HTTP %s)" % (
            record.get("httpCode") or "000")
    if status == "invalid":
        return "artifact served but not a valid document"
    return "not collected (%s)" % status


def build_sources(host_state, host_dir, aws_freshness_hours):
    sources = {}
    for artifact in ARTIFACTS:
        record = host_state.get(artifact)
        if record is None or record.get("status") != "ok":
            sources[artifact] = {
                "collected": False,
                "reason": skip_reason(record),
            }
            continue
        entry = {
            "collected": True,
            "sha256": record.get("sha256"),
            "fetchedAt": record.get("fetchedAt"),
        }
        if artifact == "hasp.json":
            doc = host_doc(host_dir, artifact) or {}
            entry["profileHash"] = doc.get("haspHash")
            entry["fleetHash"] = doc.get("fleetHash")
        if artifact == "hasp-aws.json":
            entry["stale"] = aws_is_stale(
                os.path.join(host_dir, artifact),
                record.get("fetchedAt"),
                aws_freshness_hours,
            )
        sources[artifact] = entry

    # One entry per sealed day, so a report over a period can cite the digest of
    # every record it read rather than asserting the period was covered.
    #
    # Digested from the stored file rather than taken from this run's fetch
    # outcomes: a record is fetched once and skipped on every later run, so a
    # monthly report would otherwise carry no digest for any day it actually used.
    days = {}
    obs_dir = os.path.join(host_dir, "observations")
    if os.path.isdir(obs_dir):
        for name in sorted(os.listdir(obs_dir)):
            if not name.endswith(".json") or name == "index.json":
                continue
            path = os.path.join(obs_dir, name)
            try:
                with open(path, "rb") as fh:
                    digest = hashlib.sha256(fh.read()).hexdigest()
            except OSError as e:
                warn("%s unreadable (%s)" % (path, e))
                continue
            entry = {"sha256": digest}
            fetched = (host_state.get("observations/" + name) or {}).get("fetchedAt")
            if fetched:
                entry["fetchedAt"] = fetched
            days[name[:-len(".json")]] = entry
    if days:
        sources["observations"] = {"collected": True, "days": days}
    return sources


def aws_is_stale(path, fetched_at, freshness_hours):
    doc = load_json(path)
    last = doc.get("lastCollected") if isinstance(doc, dict) else None
    if not last or not fetched_at:
        return True
    try:
        gap = parse_stamp(fetched_at) - parse_stamp(last)
    except ValueError:
        return True
    return gap > timedelta(hours=freshness_hours)


def build_profile(host_dir, host_state):
    if host_state.get("hasp.json", {}).get("status") != "ok":
        return None
    hasp = host_doc(host_dir, "hasp.json")
    if hasp is None:
        return None

    facts = dict(hasp.get("facts") or {})
    profile = {
        "host": hasp.get("host"),
        "haspHash": hasp.get("haspHash"),
        "fleetHash": hasp.get("fleetHash"),
        "haspSchemaVersion": hasp.get("schemaVersion"),
        "registryVersion": hasp.get("registryVersion"),
        "declaredReview": hasp.get("declaredReview"),
        "fleet": hasp.get("fleet") or {},
        "aws": None,
    }

    if host_state.get("hasp-aws.json", {}).get("status") == "ok":
        aws = host_doc(host_dir, "hasp-aws.json")
        if aws:
            facts.update(aws.get("facts") or {})
            profile["aws"] = {
                "tier": aws.get("tier"),
                "instanceId": aws.get("instanceId"),
                "region": aws.get("region"),
                "lastCollected": aws.get("lastCollected"),
                "collectionCount": aws.get("collectionCount"),
                "changedKeys": aws.get("changedKeys") or [],
            }

    profile["facts"] = facts
    return profile


def merge_sockets(records):
    """Union sockets.observed across the days, summing samples per key.

    A socket bound briefly under load appears on one day only, so a negative
    reachability claim needs every day of the period, not the newest record.
    """
    observed = {}
    for rec in records:
        for key, entry in ((rec.get("sockets") or {}).get("observed") or {}).items():
            into = observed.setdefault(key, {"addresses": set(), "units": set(),
                                             "users": set(), "samples": 0,
                                             "lastSeen": None})
            into["addresses"].update(entry.get("addresses") or [])
            into["units"].update(entry.get("units") or [])
            into["users"].update(entry.get("users") or [])
            into["samples"] += entry.get("samples") or 0
            seen = entry.get("lastSeen")
            if seen and (into["lastSeen"] is None or seen > into["lastSeen"]):
                into["lastSeen"] = seen
    return observed


def build_exposure(host_dir, host_state):
    records = daily_records(host_dir)
    if not records:
        return {"collected": False, "socketObservation": False, "sockets": []}

    newest = records[-1]
    observed = merge_sockets(records)
    current = (newest.get("sockets") or {}).get("current") or []
    doc = newest
    if not observed and not current:
        return {
            "collected": True,
            "socketObservation": False,
            "sockets": [],
            "daysExamined": len(records),
        }

    listed = []
    for key, entry in observed.items():
        port, _, rest = key.partition("/")
        proto, _, bind_class = rest.partition("/")
        try:
            port = int(port)
        except ValueError:
            warn("socket key %r has a non-numeric port, kept as string" % key)
        listed.append({
            "port": port,
            "proto": proto,
            "bindClass": bind_class,
            "addresses": sorted(entry["addresses"]),
            "units": sorted(entry["units"]),
            "users": sorted(entry["users"]),
            "samples": entry["samples"],
            "lastSeen": entry["lastSeen"],
        })
    listed.sort(key=lambda s: (str(s["port"]), s["proto"], s["bindClass"]))

    return {
        "collected": True,
        "socketObservation": True,
        "sockets": listed,
        "current": current,
        "unitUsers": (doc.get("units") or {}).get("user") or {},
        "daysExamined": len(records),
        "daysComplete": sum(1 for r in records if r.get("complete")),
    }


def daily_records(host_dir):
    """Sealed daily records for a host, oldest first."""
    d = os.path.join(host_dir, "observations")
    if not os.path.isdir(d):
        return []
    out = []
    for name in sorted(os.listdir(d)):
        if not name.endswith(".json") or name == "index.json":
            continue
        doc = load_json(os.path.join(d, name))
        if isinstance(doc, dict) and doc.get("sealed"):
            out.append(doc)
    return out


def coverage_of(records):
    """(days examined, days complete, first date, last date)."""
    if not records:
        return 0, 0, None, None
    complete = sum(1 for r in records if r.get("complete"))
    dates = [r.get("date") for r in records if r.get("date")]
    return len(records), complete, (min(dates) if dates else None), (max(dates) if dates else None)


def inuse_units(records, dedup):
    """Group key -> units observed holding that package, across the period."""
    units = {}
    for rec in records:
        for name, entry in ((rec.get("inuse") or {}).get("observed") or {}).items():
            if not isinstance(entry, dict):
                continue
            units.setdefault(group_key(name, dedup), set()).update(entry.get("units") or [])
    return {k: sorted(v) for k, v in units.items()}


def load_inuse(records, dedup):
    """In-use group keys observed in the period, or None meaning unknown.

    None must never be read as "nothing is in use". A period with no complete day
    could not have observed the code, so it says nothing either way rather than
    licensing a negative claim.
    """
    examined, complete, _, _ = coverage_of(records)
    if examined == 0:
        warn("no sealed daily records; findings reported as inuse=unknown")
        return None
    if complete == 0:
        warn("no complete day among %d sealed record(s); findings reported as "
             "inuse=unknown" % examined)
        return None
    keys = set()
    for rec in records:
        for name in ((rec.get("inuse") or {}).get("observed") or {}):
            keys.add(group_key(name, dedup))
    return keys


def build_findings(host_dir, inuse_keys, dedup, exclusions, units_by_group=None):
    path = os.path.join(host_dir, "output.json")
    if not os.path.isfile(path):
        return [], None
    doc = load_json(path)
    if not isinstance(doc, list):
        warn("%s is not a vulnix result list" % path)
        return [], None

    groups = {}
    meta = {}
    for entry in doc:
        pname = entry.get("pname") or ""
        vendors = entry.get("cpe_vendors") or {}
        scores = entry.get("cvssv3_basescore") or {}
        key = group_key(entry.get("name", ""), dedup)
        bucket = groups.setdefault(key, {})
        meta.setdefault(key, {"pname": pname, "version": entry.get("version")})
        for cve in entry.get("affected_by") or []:
            if vendor_excluded(pname, vendors.get(cve), exclusions):
                continue
            if bucket.get(cve) is None:
                bucket[cve] = scores.get(cve)

    findings = []
    for key in sorted(groups):
        if inuse_keys is None:
            in_use = "unknown"
        else:
            in_use = key in inuse_keys
        for cve in sorted(groups[key]):
            score = groups[key][cve]
            findings.append({
                "cve": cve,
                "package": key,
                "pname": meta[key]["pname"],
                "version": meta[key]["version"],
                "cvss": score,
                "severity": cvss_to_severity(
                    float(score) if score is not None else None),
                "inUse": in_use,
                "units": (units_by_group or {}).get(key, []),
            })

    summary = {
        "packages": len({f["package"] for f in findings}),
        "packagesFlagged": len(groups),
        "findings": len(findings),
        "distinctCves": len({f["cve"] for f in findings}),
    }
    return findings, summary


def build_images(trivy_host_dir):
    images = []
    if not os.path.isdir(trivy_host_dir):
        return images
    for slug in sorted(os.listdir(trivy_host_dir)):
        path = os.path.join(trivy_host_dir, slug, "output.json")
        if not os.path.isfile(path):
            continue
        doc = host_doc(os.path.join(trivy_host_dir, slug), "output.json")
        if doc is None:
            continue
        findings = []
        for result in doc.get("Results") or []:
            for vuln in result.get("Vulnerabilities") or []:
                findings.append({
                    "cve": vuln.get("VulnerabilityID"),
                    "package": vuln.get("PkgName"),
                    "version": vuln.get("InstalledVersion"),
                    "fixedVersion": vuln.get("FixedVersion"),
                    "severity": (vuln.get("Severity") or "UNKNOWN").upper(),
                    "target": result.get("Target"),
                })
        images.append({
            "slug": slug,
            "artifactName": doc.get("ArtifactName"),
            "findings": findings,
            "summary": {
                "findings": len(findings),
                "distinctCves": len({f["cve"] for f in findings if f["cve"]}),
            },
        })
    return images


def write_atomic(path, payload):
    directory = os.path.dirname(path)
    os.makedirs(directory, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=directory, suffix=".tmp")
    try:
        with os.fdopen(fd, "w") as fh:
            json.dump(payload, fh, indent=1, sort_keys=True)
        os.chmod(tmp, 0o644)
        os.replace(tmp, path)
    except BaseException:
        os.unlink(tmp)
        raise


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--run-id", required=True)
    parser.add_argument("--state", required=True)
    parser.add_argument("--configured", required=True)
    parser.add_argument("--vulnix-dir", required=True)
    parser.add_argument("--trivy-dir", required=True)
    parser.add_argument("--out", required=True)
    parser.add_argument("--aws-freshness-hours", type=int, default=48)
    parser.add_argument("--deduplicate-outputs", type=int, default=1)
    parser.add_argument("--vendor-exclusions", default="{}")
    args = parser.parse_args()

    configured = json.loads(args.configured)
    exclusions = json.loads(args.vendor_exclusions)
    dedup = bool(args.deduplicate_outputs)
    state = read_state(args.state)

    collected = []
    skipped = []
    for name in configured:
        record = state.get(name, {}).get("packages.json")
        if record is not None and record.get("status") == "ok":
            collected.append(name)
        else:
            skipped.append({"host": name, "reason": skip_reason(record)})

    hosts = {}
    for name in collected:
        host_dir = os.path.join(args.vulnix_dir, name)
        host_state = state.get(name, {})
        records = daily_records(host_dir)
        examined, complete, first, last = coverage_of(records)
        inuse_keys = load_inuse(records, dedup)
        units_by_group = inuse_units(records, dedup) if inuse_keys is not None else {}
        findings, summary = build_findings(host_dir, inuse_keys, dedup, exclusions,
                                           units_by_group)
        hosts[name] = {
            "observation": {
                "daysExamined": examined,
                "daysComplete": complete,
                "firstDay": first,
                "lastDay": last,
            },
            "sources": build_sources(host_state, host_dir, args.aws_freshness_hours),
            "profile": build_profile(host_dir, host_state),
            "exposure": build_exposure(host_dir, host_state),
            "findings": findings,
            "summary": summary,
            "images": build_images(os.path.join(args.trivy_dir, name)),
        }

    bundle = {
        "schemaVersion": SCHEMA_VERSION,
        "runId": args.run_id,
        "generatedAt": now_stamp(),
        "coverage": {
            "configured": list(configured),
            "collected": collected,
            "skipped": skipped,
        },
        "hosts": hosts,
        "normalizerWarnings": warnings,
    }

    write_atomic(args.out, bundle)
    print("evidence bundle written: %d of %d host(s) collected, %d warning(s)"
          % (len(collected), len(configured), len(warnings)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
