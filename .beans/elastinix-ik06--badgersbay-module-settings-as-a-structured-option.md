---
# elastinix-ik06
title: 'badgersbay module: settings as a structured option rendered to YAML'
status: completed
type: task
priority: high
created_at: 2026-09-16T15:51:46Z
updated_at: 2026-09-16T16:55:15Z
parent: elastinix-l16a
---

`configFile` defaults to a `pkgs.writeText` heredoc holding the whole
badgersbay configuration. Nothing inside that block is an option, so a host
that needs one value different has to override the entire file - and then the
module's own defaults never reach it again.

That is not theory. compute2 sets

    configFile = config.age.secrets.badgersbay-config.path;

and when the module default moved from neofetch to fastfetch (elastinix-22iq),
the change did not reach the production host.

## Scope

Replace the heredoc with `settings`, a freeform submodule rendered through
`pkgs.formats.yaml`. Declared keys, matching what `Config.load()` in
honeybadger_server.py actually reads at the pinned revision 47e6cb6:

    networkport                            defaults from `port`
    storage_location                       defaults from `storagePath`
    compliance.enabled                     true
    compliance.audit_months                [3 9]
    compliance.grace_weeks                 4
    compliance.required_reports.mandatory  [fastfetch lynis]
    compliance.required_reports.one_of     []
    compliance.required_reports.per_class  {} - class -> requirement -> tools

Freeform, so a key the server gains can be set before the module knows it.

## Boundary

No secret becomes a value here. `settings` may be a real option precisely
because nothing in it is secret; `tokenFile`, `dashboardPasswordFile` and
`assetRegisterFile` stay paths pointing at agenix secrets. No `tokens = [ ... ]`
option, ever.

`compliance.asset_register` is not exposed: the register arrives as
`--asset-register`, which overrides the config file, so a value set there would
be silently discarded.

## configFile

Stays, and still wins when set - compute2 depends on it. But an explicit
`configFile` together with an explicit `settings` is an assertion failure
rather than a silent discard.

## Todo

- [ ] `settings` option with the declared keys above and a freeform type
- [ ] `configFile` defaults to the rendered file
- [ ] Assertion on setting both
- [ ] Assertion that `settings.compliance.asset_register` is not set
- [ ] Evaluate a real NixOS configuration and read the rendered YAML
