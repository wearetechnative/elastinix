## 1. Flake Input

- [x] 1.1 Add `jiraticketcreate` flake input to `flake.nix` with `inputs.nixpkgs.follows = "nixpkgs"`
- [x] 1.2 Pass `inputs` to the NixOS module so `inputs.jiraticketcreate.packages.${pkgs.system}.default` is accessible
- [ ] 1.3 Run `nix flake update jiraticketcreate` to lock the input

## 2. NixOS Module

- [ ] 2.1 Create `modules/nixos/services/service-jiraticketcreate.nix` with `elastinix.services.jiraticketcreate.enable` option
- [ ] 2.2 Add `checkTypes` attrset option with submodule: `frequency` (required), `titleTemplate` (required), `description` (required), `issueType` (optional, default `"Task"`), `dueDateOffsetDays` (optional, default `0`)
- [ ] 2.3 Add `jiraUrl` and `jiraUser` string options at module level (required, no default)
- [ ] 2.4 Add `clients` attrset option with submodule: `board`, `checks` (list of check type names), `tokenSecretPath` (path to agenix secret containing raw API token), `jiraUrl` (`nullOr str`, default `null`), `jiraUser` (`nullOr str`, default `null`)
- [ ] 2.5 Implement cross-product generation: for each client, for each check in `client.checks`, generate a named instance `<client>-<checkType>`
- [ ] 2.6 Generate `environment.etc."jiraticketcreate/<instance>.json"` entries with static ticket fields (board, issue_type) only; `api` block is assembled at runtime in the service script
- [ ] 2.7 Write frequency logic as Nix strings per supported `frequency` value; the NixOS module selects and inlines the correct bash function into each generated service script using Nix `if/else` on the `frequency` value; add `lib.throwIf` for unsupported values. Functions to implement: `is_first_working_day_of_month`, `is_first_working_day_of_quarter`, `is_first_working_day_of_week`, `get_current_period` (returns period string e.g. `"2026-06"` or `"2026-Q2"` depending on frequency)
- [ ] 2.8 Assemble systemd `ExecStart` script: check frequency → render title with period substitution → compute `due_date` as `$(date -d "+<dueDateOffsetDays> days" +%Y-%m-%d)` → write temp JSON with `api` block (`url`, `user`, `token_file` from NixOS config) and `ticket` block (`board`, `issue_type`, rendered `title`, `description`, `due_date`) → call `jiraticketcreate --config <tmp>`
- [ ] 2.9 Generate `systemd.services."jiraticketcreate-<instance>"` as `Type = oneshot` with standard elastinix hardening
- [ ] 2.10 Generate `systemd.timers."jiraticketcreate-<instance>"` with `OnCalendar = "daily"` and `Persistent = true`
- [ ] 2.11 Import the new module in `modules/nixos/default.nix` (or equivalent module list)

## 3. Verification

- [ ] 3.1 Run `nix build` to verify the module evaluates without errors
- [ ] 3.2 Configure one test instance in a host NixOS config and verify systemd service + timer are generated
- [ ] 3.3 Write service documentation in `docs/services/jiraticketcreate.md`
