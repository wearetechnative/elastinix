---
# elastinix-ac79
title: 'service-jiraticketcreate: always add jiraticketcreate-elastinix label + optional extra labels'
status: in-progress
type: task
created_at: 2026-06-24T00:00:00Z
updated_at: 2026-06-24T00:00:00Z
---

The `service-jiraticketcreate` NixOS module should always include a `"jiraticketcreate-elastinix"` label on every ticket it creates, so tickets are always traceable to their origin. Users can add extra labels via an optional `labels` field on `checkTypes`.

The module prepends the fixed label itself — users cannot accidentally omit it. Extra labels are optional and default to `[]`.

Depends on: [jiraticketcreate-1fb4](../../jiraticketcreate/.beans/jiraticketcreate-1fb4--add-labels-support.md) (Python-side labels support)
