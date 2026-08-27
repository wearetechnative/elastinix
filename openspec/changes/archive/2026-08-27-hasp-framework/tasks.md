## 1. HASP module foundation

- [x] 1.1 Create `modules/nixos/services/service-hasp.nix` with an `enable` option defaulting to `false`, following the existing service module pattern
- [x] 1.2 Define the fact record type: `value`, `source` (enum `derived`/`declared`/`aws`/`observed`), `evidence`, with `evidence` required
- [x] 1.3 Define the fact registry as a closed attribute set keyed by dotted fact name, carrying expected type and source per key, with `registryVersion`
- [x] 1.4 Add an assertion that fails the build on any fact key absent from the registry, naming the offending key
- [x] 1.5 Add an assertion that fails the build on a list fact that is not sorted
- [x] 1.6 Verify no registered fact reads package names, versions, or an enumeration of an upstream-defined set

## 2. Declared facts

- [x] 2.1 Add the `declared` submodule with `environment`, `role`, `owner`, `dataClassification`, `isJumphost` — all without defaults
- [x] 2.2 Add `reviewedBy` and `reviewedAt` as required block-level options
- [x] 2.3 Add assertions that fail the build when any declared fact or review field is missing, naming it
- [x] 2.4 Constrain `environment` and `dataClassification` to their enums via `lib.types.enum`
- [x] 2.5 Confirm no default is substituted anywhere: grep the module for `default =` on any declared option

## 3. Derived and fleet facts

- [x] 3.1 Implement `network.firewallOpenPorts` from `networking.firewall.allowed{TCP,UDP}Ports`
- [x] 3.2 Implement `runtime.dockerEnabled` and `runtime.nixosStateVersion`
- [x] 3.3 Implement `runtime.localDatabases` as a closure projection covering the engines actually used in this repo, labelled as a partial list
- [x] 3.4 Implement the `fleet` section: `systemdHardeningDefault`, `fail2banEnabled`, `auditdEnabled`, `centralLogShipping`, `sshPasswordAuthentication`, `inUseSamplerEnabled`
- [x] 3.5 Record `base-system.nix:5` as the evidence string for `fleet.fail2banEnabled`, and "absent from modules/" for the two absent controls

## 4. Hashing and document generation

- [x] 4.1 Compute `haspHash` over host fact `value` fields only, excluding `evidence`, `source` and the review stanza
- [x] 4.2 Compute `fleetHash` over fleet fact values, excluded from `haspHash`
- [x] 4.3 Emit the document with `schemaVersion`, `registryVersion`, `host`, both hashes, `declaredReview`, `facts` and `fleet`, and no generation timestamp
- [x] 4.4 Materialise the document as a store path — no generator service, no timer
- [x] 4.5 Verify two evaluations of an unchanged configuration produce an identical store path
- [x] 4.6 Verify an unrelated nixpkgs bump leaves `haspHash` unchanged

## 5. AWS fact collection on the host

- [x] 5.1 Add the `awsFacts` enum option (`none`/`metadata`/`api`) and `awsFactsIntervalSeconds`
- [x] 5.2 Emit the fact registry into the closure as `hasp-registry.json`
- [x] 5.3 Implement the metadata tier from IMDSv2: security group ids, subnet id, public-IP presence — no AWS credentials
- [x] 5.4 Implement the api tier: ingress rules, internet-reachable ports, all-ports-open, reachable-from-groups, subnet tier, load balancer attachment, attached volumes
- [x] 5.5 Handle the VPC main route table fallback for subnets with no explicit association
- [x] 5.6 Record a very wide world-facing range as `internetAllPortsOpen` rather than expanding it
- [x] 5.7 Validate collected facts against the registry manifest before writing; refuse on unregistered key, wrong type or unsorted list
- [x] 5.8 Keep the previous document and exit non-zero on any collection failure — never write a partial document
- [x] 5.9 Write atomically and chmod 644, since the HTTP server runs unprivileged
- [x] 5.10 Add boto3 to the interpreter only on the api tier; measure the closure cost
- [x] 5.11 Document the tiers, their IAM cost and the read-only actions the api tier needs

## 6. Socket and unit-user observation

- [x] 6.1 Extend the sampler to enumerate listening sockets with port, protocol and bind address
- [x] 6.2 Derive `bindClass` as `loopback`/`wildcard`/`specific`, treating the IPv6 wildcard as `wildcard`, retaining the raw address
- [x] 6.3 Attribute each socket to its owning unit and user via pid and cgroup, recording empty attribution rather than guessing
- [x] 6.4 Build the `units.user` map from observed processes
- [x] 6.5 Maintain both the cumulative `observed` map with sample counts and last-seen timestamps, and the `current` snapshot
- [x] 6.6 Publish `schemaVersion`, `intervalSeconds`, `firstSample`, `lastSample`, `sampleCount` in the document
- [x] 6.7 Write the document atomically and set world-readable permissions explicitly, since the temporary file defaults to owner-only and the HTTP server runs unprivileged
- [x] 6.8 Confirm the sampler unit sets neither `ProtectProc` nor `PrivateUsers`, and carries a comment explaining why
- [x] 6.9 Verify on a live host that a loopback-bound service is recorded as `loopback` and a wildcard-bound one as `wildcard`

## 7. Serving the documents

- [x] 7.1 Add tmpfiles rules: `hasp.json` symlinked from the closure, `hasp-aws.json` from the collector state directory
- [x] 7.2 Add the symlink rule for `runtime-facts.json`
- [x] 7.3 Verify all three are retrievable over the configured port as the unprivileged server user
- [x] 7.4 Verify none is present when its feature is disabled

## 8. Change detection

- [x] 8.1 Compare each collection against the previously published document
- [x] 8.2 Report changed keys with their previous and current values, and exit non-zero so the event is alertable
- [x] 8.3 Record `lastChanged` per fact and `changedKeys` for the latest transition
- [x] 8.4 Treat the first collection as no change
- [x] 8.5 Distinguish collection failure from no-change by exit code, so unavailability is never read as agreement
- [x] 8.6 Add the collector unit and timer, hardened, with write access only to its state directory
- [x] 8.7 Restrict the metadata tier to the link-local metadata address only; document why the api tier cannot be
- [x] 8.8 Verify against a metadata stub: no-change, change with both values, unreachable, registry rejection

## 9. Documentation

- [x] 9.1 Write `docs/services/hasp.md` covering options, the three documents, the fact registry, and the two verification layers
- [x] 9.2 Add the service to `docs/README.md`
- [x] 9.3 Update `docs/services/hostinfo.md` for the three new served documents and the socket observation
- [x] 9.4 Cross-reference `docs/hasp-framework.md` and `docs/vulnix-cve-automation.md` from the service docs
- [x] 9.5 Add a CHANGELOG entry
- [x] 9.6 Record in the docs that the on-host check cannot see in-group rule changes, and that the daily comparison covers it within 24 hours

## 10. Verification

- [x] 10.1 `nix flake check` passes
- [x] 10.2 `nix build` the configuration for a host with HASP enabled
- [x] 10.3 Confirm the build fails with a clear assertion when a declared fact is removed
- [x] 10.4 Confirm the build fails with a clear assertion when `hasp-aws.json` is absent
- [x] 10.5 Confirm the build fails with a clear assertion on an unregistered fact key
- [x] 10.6 Deploy to one non-production host and fetch all three documents over port 3333
- [x] 10.7 Verify every fact value in the served document is JSON-comparable
- [x] 10.8 `openspec validate hasp-framework` passes

## 11. Cross-repo and follow-up

- [x] 11.1 ~~Propose the AWS collector in the workloads repo~~ — superseded: collection runs on the host
- [x] 11.2 ~~Propose the daily comparison job~~ — superseded: change detection is a property of collection
- [x] 11.3 Record the decision: `hasp-aws.json` is never in the repo; it is collected on the machine
- [x] 11.4 Note for a future change: remove the stale *Optional SBOM exposure* requirement from `openspec/specs/hostinfo-service`
- [x] 11.5 Create the epic bean for this work and add its link to `proposal.md`
