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

## 4. Rollout

- [ ] 4.1 Deploy compute3 non-production and confirm `[garbage-collection]` is
  present in the running configuration and that the collector logs a pass.
- [ ] 4.2 Deploy compute3 production and confirm the same; record in the
  workloads ledger (`stack/ec2_compute3/attic-tokens.md`) that `tn-infra` now
  inherits a 90-day retention, replacing the note that says nothing expires.

## 5. Validation

- [ ] 5.1 Run `openspec validate attic-garbage-collection --strict` and resolve
  any findings.
