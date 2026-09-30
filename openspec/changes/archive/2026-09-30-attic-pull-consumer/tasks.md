# Tasks

## 1. Module and evaluation test

- [x] 1.1 Create `modules/nixos/services/service-attic-pull.nix` with the
  `elastinix.services.attic_pull` option set (`enable`, `endpoint`, `cache`,
  `public_key`, `netrc_file`; design D1–D3), and the `nix.settings` it renders
  when enabled (design D4). Verify by evaluating a host with the module enabled
  and reading `nix.settings`.
- [x] 1.2 Add the assertions from the spec (missing values, endpoint scheme,
  cache name, public-key shape with a separate secret-key message, absolute
  netrc path; design D5). Verify that a valid configuration evaluates and that
  each broken variant fails with its own message.
- [x] 1.3 Add `tests/attic-pull.nix` as an evaluation test covering: the
  disabled no-op, upstream kept and ordered first, trailing-slash
  normalisation, `netrc-file`, no extra systemd unit, and every assertion in
  both directions. Wire it into `flake.nix` as `checks.<system>.attic-pull`.
  Verify with `nix build .#checks.x86_64-linux.attic-pull`, and check that
  breaking a rendered value makes it fail.

## 2. End-to-end VM test

- [x] 2.1 Add `tests/attic-pull-vm.nix`: a two-node `runNixOSTest`. The
  `server` runs upstream `services.atticd` with local storage and a private
  cache created through the API with a committed throwaway keypair (design D7).
  The `client` has `attic_pull` enabled. The client must fail to realise a
  runtime-generated path without a netrc, and succeed once the netrc is
  present. Wire it into `flake.nix` as `checks.<system>.attic-pull-vm`.
  Verify with `nix build .#checks.x86_64-linux.attic-pull-vm`.

## 3. Documentation

- [x] 3.1 Write `docs/services/attic-pull.md`: the options table, the netrc
  format and its `machine`-must-match-host rule, the agenix snippet
  (`owner = "root"`, `mode = "400"`), the ordering and priority behaviour, and
  the trust implication of `public_key`. Link it from `docs/README.md`. Verify
  that the documented example evaluates, by using it as the valid
  configuration in `tests/attic-pull.nix`.

## 4. Integration

- [x] 4.1 Run `nix flake check --no-build` and build every `checks` entry for
  x86_64-linux (`attic-pull`, `attic-pull-vm`, and the existing attic checks,
  to confirm no regression). Verify that all of them succeed.
