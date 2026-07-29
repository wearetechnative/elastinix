## Context

`service-jiraticketcreate.nix` generates a JSON config at runtime via `jq` and passes it to the `jiraticketcreate` binary. The `jiraticketcreate` tool (after its `add-labels-support` change) accepts an optional `labels` array in the `ticket` section of this JSON.

The module currently handles the optional `status` field with a conditional `--arg`/jq-interpolation pattern. Labels follow the same pattern but use `--argjson` because the value is a JSON array, not a string.

## Goals / Non-Goals

**Goals:**
- Guarantee every ticket created by this module carries `"jiraticketcreate-elastinix"` as a label.
- Allow users to add extra labels per `checkType`.
- Keep the fixed label unremovable by users (enforced in the module, not in user config).

**Non-Goals:**
- Labels at the `clients` level (checkType is the right scope for ticket characteristics).
- Validating that labels exist in Jira before creation.
- Removing or updating labels on already-created tickets.

## Decisions

**Fixed label prepended by the module, not configurable**
The label `"jiraticketcreate-elastinix"` is hardcoded in the module and concatenated with user labels:
```nix
effectiveLabels = [ "jiraticketcreate-elastinix" ] ++ ct.labels;
```
Alternative (optional default label) was rejected: users could set `labels = []` and lose traceability. The fixed label guarantees origin is always visible.

**`labels` option on `checkTypes`, not `clients`**
Ticket characteristics (what kind of ticket, what labels) belong on the template level. Client config is about where and who, not what. Consistent with `issueType`, `status`, `titleTemplate`.

**`--argjson` for the labels array**
The `jq` call in `mkScript` uses `--arg` for strings. Arrays require `--argjson`. The effective labels list is serialized with `builtins.toJSON` at Nix evaluation time:
```nix
--argjson labels '${builtins.toJSON effectiveLabels}'
```
This is safe: `builtins.toJSON` always produces valid JSON.

**`labels` defaults to `[]`, type `types.listOf types.str`**
The user supplies zero or more extra labels. The module always adds the fixed one. An empty user list is valid and common.

## Risks / Trade-offs

- [Upstream dependency] This change requires the `jiraticketcreate` flake input to be updated to a version that supports `labels`. Until then, the generated config would include a `labels` field that the old Python tool ignores silently — no breakage, but no effect either.
- [Label string content] No validation of label content (casing, special characters). Jira accepts arbitrary strings; invalid characters may cause a 400 from the API, which the tool already surfaces as an error.
