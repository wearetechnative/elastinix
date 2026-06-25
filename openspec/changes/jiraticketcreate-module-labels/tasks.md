# Tasks

## service-jiraticketcreate.nix

- [x] Add `labels` option to `checkTypes` submodule (`types.listOf types.str`, default `[]`)
- [x] Compute `effectiveLabels = [ "jiraticketcreate-elastinix" ] ++ ct.labels` in `mkScript`
- [x] Add `--argjson labels '${builtins.toJSON effectiveLabels}'` to the `jq` call in `mkScript`
- [x] Add `, labels: $labels` to the `ticket` object in the `jq` filter

## Validation

- [x] Build a NixOS config using the module without `labels` set — verify generated JSON contains `["jiraticketcreate-elastinix"]`
- [x] Build a NixOS config with `labels = [ "extra" ]` — verify generated JSON contains `["jiraticketcreate-elastinix", "extra"]`
- [x] Confirm upstream `jiraticketcreate` flake input is updated to a version supporting `labels`
