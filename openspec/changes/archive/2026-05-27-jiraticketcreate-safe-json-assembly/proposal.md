## Why

The `service-jiraticketcreate` module constructs its JSON config payload via a bash heredoc with direct string interpolation. This breaks silently when `description`, `titleTemplate`, or any other field contains newlines, quotes, or backslashes — making multiline descriptions impossible and leaving all fields vulnerable to JSON injection. Fixing this now prevents silent failures in production and opens up expressive ticket descriptions.

Related task: [elastinix-0dlx](/.beans/elastinix-0dlx--jiraticketcreate-support-multiline-descriptions.md)

## What Changes

- Replace the heredoc JSON construction in `mkScript` with `jq -n --arg ...` assembly
- All fields — both build-time Nix strings and runtime bash variables — are passed as named `--arg` arguments to `jq`, which escapes them correctly
- Add `pkgs.jq` as a runtime dependency, referenced by absolute store path in the script
- `description` in `checkTypes.<name>` now supports multiline Nix strings (no user-facing option changes)

## Capabilities

### New Capabilities

- `jiraticketcreate-safe-json`: JSON payload construction for jiraticketcreate is safe for all string values including newlines, quotes, and special characters

### Modified Capabilities

- `jiraticketcreate-service`: The internal script assembly changes — `description` requirement now explicitly supports multiline strings

## Impact

- `modules/nixos/services/service-jiraticketcreate.nix`: `mkScript` function rewritten; `pkgs.jq` added as dependency
- `docs/services/jiraticketcreate.md`: description option documented as supporting multiline strings
- No breaking changes — all existing NixOS configurations continue to work unchanged
