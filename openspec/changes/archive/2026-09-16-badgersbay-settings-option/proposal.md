## Why

The module half-owns the badgersbay configuration. `configFile` defaults to a
`pkgs.writeText` heredoc that holds the whole file, so nothing inside it is an
option. A host that needs one value different has to override the entire file -
and from that moment the module's defaults never reach it again.

That has already cost us a production incident. compute2 sets

    configFile = config.age.secrets.badgersbay-config.path;

so when the module's required report type moved from `neofetch` to `fastfetch`
(elastinix-22iq), the change did not reach the host. The real configuration
lived in a secret that had to be updated separately, and until it was, every
system was recorded as incomplete.

The second half is the same failure in a different place: the three secret
files are only looked at when the service starts. A path that names a secret
nobody declared, or one agenix writes root-owned at 0400 while the service runs
as `badgersbay`, produces a green deploy and a unit that restarts every ten
seconds.

## What Changes

- **`settings`**, a structured option rendered to YAML through
  `pkgs.formats.yaml`, replacing the heredoc. Declared keys for everything
  `Config.load()` reads, freeform for everything it gains later.
- **`configFile` keeps winning when it is set**, because compute2 depends on
  it, but setting it together with `settings` is now an evaluation error rather
  than a silent discard.
- **Assertions** on the secret files: no store paths, no undeclared agenix
  path, no secret the service user cannot read.
- **Docs**: the new option, the configFile rule and its reasoning, the
  migration off an agenix config secret, and what the assertions do and do not
  prove.

## Capabilities

### Modified Capabilities
- `badgersbay-service`: the module owns the configuration structure, and
  refuses at evaluation a configuration that cannot work

## Impact

- A host that sets neither `settings` nor `configFile` gets the same
  configuration it gets today, rendered by a different mechanism. The keys and
  values are unchanged.
- A host that sets only `configFile` - compute2 - is unaffected, and can now
  migrate: the configuration carries no secrets, so it does not have to be one.
- A host whose agenix secrets are root-owned at 0400 and whose service runs as
  `badgersbay` now fails to evaluate. It was already failing to run; it just
  failed later and more quietly.

## Non-goals

- **No secret becomes a value.** `settings` is a real option precisely because
  nothing in it is secret. `tokenFile`, `dashboardPasswordFile` and
  `assetRegisterFile` stay paths pointing at agenix secrets, and no
  friendly-looking `tokens = [ ... ]` option is added - not now, not later.
- **No `compliance.asset_register` key.** The register arrives as
  `--asset-register`, which overrides the config file, so a value set there
  would be silently discarded. The assertion says so.
- **No claim that a secret exists.** Agenix decrypts at activation, long after
  evaluation, and `builtins.pathExists` on a build host says nothing about the
  target. The assertions check declarations, not the filesystem.
