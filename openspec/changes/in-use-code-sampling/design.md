## Context

Vulnix reports that a package version with a known CVE is present in a host's closure. It cannot say whether that code executes. For ISO 27001 evidence we need to distinguish findings in running code from findings in code that is merely on disk.

Two mechanisms were prototyped on `compute5-prod` before choosing.

**Static reachability from the store graph** — classify each package by whether it is reachable from an enabled systemd unit's `ExecStart` closure, from `system-path` only, or from neither:

| class | packages | distinct CVEs |
| --- | --- | --- |
| `service` | 27 | 188 |
| `interactive` | 6 | 68 |
| `inert` | 2 | 3 |

248 → 188 is a 24% reduction. Store references are transitive, so this over-approximates badly: `curl`, `go-1.25.4`, `unbound`, `libssh2` and `hugo` are all in `quiqr-server`'s closure and none were ever loaded. Rejected as insufficient.

**Direct observation** — read `/proc/<pid>/maps`, `/proc/<pid>/exe` and `/proc/<pid>/cmdline`. On compute5, **71 store paths** out of **907** in the closure were mapped by running processes, and attribution to units worked: `openssl-3.6.0` is loaded by `node` in `quiqr-server.service`. Chosen.

Constraints discovered while prototyping:

- A single sample is misleading. `curl` appears unloaded almost always but executes weekly during the scan itself. Only accumulation over time yields a usable claim.
- The collector must read all three `/proc` sources. `maps` + `exe` alone found 62 paths; adding `cmdline` found 71.
- `/run/current-system/sw` on compute5 resolves to a *different* `system-path` than the one in `/run/current-system`'s own closure (522 vs 526 entries). Anything deriving package sets must use the closure, not the symlink.
- Every scanned host runs hostinfo, confirmed by the operator, so the collection point already exists everywhere.

## Goals / Non-Goals

**Goals:**

- Distinguish findings in observed-executing code from findings in code never observed executing.
- Attribute observations to systemd units, so an audit statement names a service rather than asserting an inference.
- Make the strength of a "never observed" claim visible, not implied.
- Fail safe: absent or untrustworthy data must never read as "not in use".

**Non-Goals:**

- The Grafana dashboard. Lives in the `monitoring` repo; this change only produces the label and coverage metrics it needs.
- KEV and EPSS enrichment. Separate concern, separate data sources, separate change.
- Any whitelist or suppression. Nothing is hidden here; findings gain a label.
- Proving unexploitability. This produces one input to that argument, not the argument.
- Catching short-lived processes reliably. Explicitly out of reach at a practical sampling cadence.

## Decisions

### Sample continuously on each host, transport via the existing weekly fetch

The obvious architecture is a per-host exporter scraped directly by Prometheus, giving minute-fresh data. It was rejected.

**The in-use set is cumulative, not instantaneous.** Its value comes from weeks of accumulated observation, so reading it weekly loses nothing — the sampler runs constantly and the scan reads whatever has accumulated. Continuous sampling with weekly transport is equivalent for this signal.

That removes the direct-scrape architecture's only real advantage, after which the hostinfo path wins on everything else: no new Prometheus targets, no new security-group rules, no cross-host `group_left` PromQL, and it reuses the pattern already established by `packages.json`, `docker-images.json` and `services.json`.

The decisive factor is audit reconstruction. With the scan persisting `inuse.json` next to `output.json`, a single directory holds the findings and their supporting evidence, written in the same run. Reconstructing "what did we know on this date" from two independently-scraped Prometheus series is a much weaker artifact.

*Alternative rejected:* per-host exporter with the join in PromQL. Fresher, but the freshness is worthless here, and it fragments the evidence.

### Add a label rather than modify the existing metric requirement

`fix-cve-overcounting` holds an unarchived `MODIFIED` delta against the exporter's `vulnix metrics` requirement. A second `MODIFIED` delta on the same requirement would mean whichever change archives second silently overwrites the other's content, because `MODIFIED` carries full replacement text.

Expressing this change purely as `ADDED` requirements sidesteps that. It is slightly less tidy as a spec — in-use behaviour is described separately from the metric it labels — and that is the right trade for not losing work to an archive ordering accident.

### Fail to `unknown`, never to `false`

A missing or stale document must not produce `inuse="false"`. If the sampler dies, every unobserved package would otherwise appear to become "not in use", and the claim would silently *strengthen* on dead data. That is the failure mode most likely to end up in an audit finding, so it gets an explicit requirement and a third label value rather than a boolean.

### Publish sampling coverage alongside the label

A `false` label backed by three samples and one backed by eight thousand are not the same claim, and a boolean cannot express the difference. Exposing sample count and last-sample time per host keeps the label honest and lets a dashboard qualify it.

### Root, with an explicit hardening carve-out

Reading other users' `/proc/<pid>/maps` requires root. `ProtectProc=invisible` and `PrivateUsers` would both blind the sampler while leaving it apparently healthy — a silent-failure shape this pipeline already has too much of. The exclusion is stated in the spec and must be commented in the module, because it is exactly the kind of thing a later hardening sweep would add in good faith.

## Risks / Trade-offs

- **Short-lived processes are invisible.** At a five-minute cadence a three-second timer job is essentially never caught. → Do not present "never observed" as "never executes". State the cadence wherever the data is used as evidence, and pair it with the static signal where a short-lived process is plausible.
- **The observed set only grows, so `inuse="false"` counts will fall over time.** → This is correct behaviour and must be documented up front, or the first drop will be misread as a regression. `curl` will appear the first time a scan runs.
- **A sampling gap strengthens claims on stale data.** → Gap detection is a requirement, not a follow-up, and resolves to `unknown`.
- **New privileged service on every compute.** → Reads only `/proc`, writes one file, no network. Small surface, but it is a new root service on hosts that did not have one for this pipeline before.
- **Label cardinality and existing queries.** → Three values per severity per host. Trivial for Prometheus, but any existing query or alert that sums the metric without aggregating away `inuse` will fan out. Dashboards and rules need review before rollout.
- **Sampler failure is invisible without alerting.** → The coverage metric makes it detectable; an actual alert on it is dashboard work in the `monitoring` repo and is not delivered by this change.

## Migration Plan

1. Land the sampler in hostinfo, defaulting to `false`. No behaviour change anywhere.
2. Enable on one host, confirm `inuse.json` accumulates and unit attribution is populated.
3. Land the scan fetch-and-persist step. Absence is tolerated, so this is safe before every host is enabled.
4. Land the exporter join. All hosts read `unknown` until their documents exist.
5. Enable the sampler across the remaining computes.
6. Let observations accumulate before using `false` as evidence. A day is not a claim.
7. Review dashboards and alert rules for the new label, then build the Grafana panel in the `monitoring` repo.

Rollback: set `enableInUseSampler = false`. Findings revert to `unknown`; no other behaviour changes.

## Open Questions

- **What staleness bound?** Needs to be lenient enough to survive a missed timer or a reboot, strict enough that a dead sampler is caught before its data is used as evidence. Some multiple of the sampling interval, but the multiplier is a judgement call.
- **Sampling interval.** Five minutes is the prototype value and is fine for daemons. A shorter interval buys little for long-running processes and still will not catch short-lived ones reliably, so the cost/benefit is flat — worth confirming rather than assuming.
- **Does the document need pruning?** It is bounded by closure size, so roughly 900 entries at worst — small enough to ignore. But a package removed from the closure will linger in the observed set forever unless reconciled against `packages.json`.
- **Should unit attribution be exposed as a metric?** It is the strongest audit artifact but is high-cardinality and reads better in a report than on a dashboard. Currently specified as recorded in the document only, not exported.
