## Why

Tickets created by the `service-jiraticketcreate` NixOS module are indistinguishable from manually created tickets in Jira. There is no way to tell at a glance whether a ticket was created by automation or by a human. This makes auditing and tracing ticket origins impossible.

> Bean: [elastinix-ac79](../../../.beans/elastinix-ac79--jiraticketcreate-module-labels-support.md)

## What Changes

- The module always includes `"jiraticketcreate-elastinix"` as a label on every ticket it creates. This is enforced by the module itself — users cannot accidentally omit it.
- A new optional `labels` field is added to the `checkTypes` submodule for additional labels. It defaults to `[]`.
- The generated `jq` call in `mkScript` combines the fixed module label with any user-supplied labels and passes them as `--argjson labels` to the JSON config.

This change depends on `add-labels-support` in the `jiraticketcreate` repository, which adds `labels` support to the Python tool itself.

## Capabilities

### New Capabilities

- `module-labels`: The module always tags created tickets with `jiraticketcreate-elastinix`. Users may add extra labels per `checkType`.

### Modified Capabilities

<!-- none -->

## Impact

- `modules/nixos/services/service-jiraticketcreate.nix`: `checkTypes` submodule gains `labels` option; `mkScript` updated to build effective labels list.
- No changes to timer, user/group, or security hardening logic.
- Requires `jiraticketcreate` package version that supports `labels` in the ticket config.
