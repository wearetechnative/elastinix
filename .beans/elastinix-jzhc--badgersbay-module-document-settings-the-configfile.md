---
# elastinix-jzhc
title: 'badgersbay module: document settings, the configFile rule and the assertions'
status: completed
type: task
priority: high
created_at: 2026-09-16T15:52:27Z
updated_at: 2026-09-16T16:55:15Z
parent: elastinix-l16a
---

`docs/services/badgersbay.md` documents `configFile` as the way to change the
configuration, which is what the epic is removing the need for.

## Scope

- `settings`: every declared key, its default, and what the server does with
  it.
- The configFile rule: an explicit `configFile` replaces the generated file
  whole. Setting both is an evaluation error. Say why - a silent discard in
  either direction is worse than a rule.
- The migration for a host on an agenix config secret: the configuration
  carries no secrets, so it does not need to be one. Move the values to
  `settings` and drop the override, and the module's defaults reach the host
  again.
- The assertions: what each one catches, and - equally - that none of them
  prove the secret is present on the target host, because it does not exist
  until activation.
- The options table: add `settings`, `configFile` and `assetRegisterFile`,
  which the table still omits.

## Todo

- [ ] settings section with the key table
- [ ] configFile interaction rule and its reasoning
- [ ] Migration note for a host overriding configFile
- [ ] Assertions section, including their limits
- [ ] Options table brought up to date
