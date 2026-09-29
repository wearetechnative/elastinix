## 1. Module

- [x] 1.1 Add a `garbage_collection` option group to
  `modules/nixos/services/service-attic.nix`: `interval` (string, default
  `"12 hours"`) and `default_retention_period` (null-or-string, default
  `"90 days"`); verify the options appear in the module's option set.
- [x] 1.2 Render `[garbage-collection]` into `services.atticd.settings`, mapping
  `null` retention to `"0"` (design D3); verify by evaluating a host with the
  defaults and reading the generated `checked-attic-server.toml`.

## 2. Tests

- [x] 2.1 Extend the evaluation tests under `tests/` with a case asserting the
  rendered section for the defaults, for an overridden interval, and for
  `default_retention_period = null`; verify all three fail before task 1.2 and
  pass after. `tests/attic-garbage-collection.nix`, wired into `flake.nix` as
  `checks.<system>.attic-garbage-collection`. It is evaluation-only — every
  scenario is settled at evaluation time, so booting a VM would cost minutes and
  prove no more. Verified in both directions: it passes as written, and flipping
  the module default to `"30 days"` makes it fail naming both affected cases and
  printing the rendered attrset.

## 3. Documentation

- [x] 3.1 Document the option group in `docs/services/attic.md`, including the
  conjunction that governs deletion and the fact that a `.narinfo` lookup does
  not count as access (design D4); verify the wording matches the query in
  `gc.rs` rather than paraphrasing "90 days" loosely.

## 3b. The collector was invisible

Found during rollout: the configuration was live on both compute3 hosts and the
collector had run at startup, yet the journal showed nothing. atticd builds its
subscriber with `EnvFilter::from_default_env()`, so with `RUST_LOG` unset it keeps
only `error`; the collector reports exclusively at `info`. The startup lines that
made the service look healthy are `eprintln!` and bypass tracing entirely.

- [x] 3b.1 Add a `log_filter` option defaulting to `attic_server=info`, set on the
  systemd unit rather than in the environment file -- it is not a secret and it
  belongs where it can be read; verified that `null` sets nothing.
- [x] 3b.2 Extend the evaluation test with the default, an override and `null`;
  verified in both directions (flipping the default to `warn` fails the test and
  names the value).
- [x] 3b.3 Document why the service looks more talkative than it is, and which
  three lines a pass actually writes.

## 4. Rollout

- [x] 4.1 Deploy compute3 non-production and confirm `[garbage-collection]` is
  present in the running configuration and that the collector logs a pass. Both
  confirmed 2026-09-29. The unit carries `RUST_LOG=attic_server=info` and the
  collector ran at startup, seconds after the deploy rather than after the
  twelve-hour interval:

      INFO run_garbage_collection_once: Running garbage collection...
      INFO run_time_based_garbage_collection: Found 0 caches subject to time-based garbage collection
      INFO run_time_based_garbage_collection: Deleted 0 objects in total
      INFO run_reap_orphan_nars: Deleted 0 orphan NARs

  `Found 0 caches` is correct here: non-production holds no caches at all, which
  the reconciliation check confirms. The orphan-chunk line is absent because
  `run_reap_orphan_chunks` returns early when there are none. So this proves the
  collector runs and reports; it does not prove that a cache is subject to
  retention. That is what task 4.2 establishes.

- [ ] 4.2 Deploy compute3 production and confirm the same; record in the
  workloads ledger (`stack/ec2_compute3/attic-tokens.md`) that `tn-infra` now
  inherits a 90-day retention, replacing the note that says nothing expires.

## 5. Validation

- [ ] 5.1 Run `openspec validate attic-garbage-collection --strict` and resolve
  any findings.
