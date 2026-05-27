## 1. Module Update

- [x] 1.1 In `mkScript` in `modules/nixos/services/service-jiraticketcreate.nix`, replace the `cat > "$TMPFILE" << JIRAEOF ... JIRAEOF` heredoc block with a `${pkgs.jq}/bin/jq -n --arg ...` invocation that passes all fields as named arguments
- [x] 1.2 Verify all fields are covered: `url`, `user`, `token_file`, `board`, `title` (runtime `$TITLE`), `description` (build-time `ct.description`), `issue_type`, `due_date` (runtime `$DUE_DATE`)

## 2. Documentation

- [x] 2.1 Update `docs/services/jiraticketcreate.md` options table: add note to `description` row that multiline Nix strings are supported
- [x] 2.2 Add a multiline description example to the configuration example in `docs/services/jiraticketcreate.md`

## 3. Verification

- [x] 3.1 Run `nix flake check` to verify the module evaluates without errors
- [x] 3.2 Update CHANGELOG under `## Next version` with the fix
