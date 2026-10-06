Bean: [elastinix-pgb5](../../../../.beans/elastinix-pgb5--provide-a-generic-attic-pull-consumer-module.md)

## Why

Elastinix ships the server side of the internal Attic cache
(`elastinix.services.attic`). The client side, which makes a host pull from that
cache, lives in `technative-awsaccounts-workloads` as
`lib/ec2nix/nix-lib/attic-pull.nix` and reads its endpoint, cache name and
public key from that repository's tfvars. A review of workloads PR #222 asked
for it to move to elastinix. Consuming an Attic cache is not specific to one
repository, and the logic is easy to get wrong without noticing. Three Nix
settings have to change together. A mistake in any of them doesn't raise an
error; deploys just get slower because Nix builds what it could have fetched:

- a substituter without the trusted key makes Nix refuse what it fetches
- a netrc without the substituter hands credentials to a cache Nix never asks
- a bare `substituters = [ … ]` assignment drops `cache.nixos.org`

## What Changes

- A new module `elastinix.services.attic_pull` that makes a host a pull consumer
  of a private Attic cache, with options `enable`, `endpoint`, `cache`,
  `public_key` and `netrc_file`.
- The module appends the cache (`<endpoint>/<cache>`) to
  `nix.settings.substituters` and its key to `nix.settings.trusted-public-keys`
  with `mkAfter`, so existing substituters such as `cache.nixos.org` are kept.
  It also points `nix.settings.netrc-file` at `netrc_file`.
- `netrc_file` is a path to a netrc that has already been decrypted, so the
  module doesn't depend on agenix. The documentation shows the agenix secret
  that provides the file.
- Evaluation-time assertions reject a missing endpoint, cache, public key or
  netrc path, as well as malformed values, with messages that name the option
  to fix.
- The module has no knowledge of tfvars or of the workloads repository.

## Capabilities

### New Capabilities

- `attic-pull-service`: what the Attic pull-consumer module configures on a
  host, and what it refuses to evaluate.

### Modified Capabilities

_None._ The attic server capability (`attic-service`) is unchanged.

## Impact

- New `modules/nixos/services/service-attic-pull.nix`. `import-tree` picks it up
  automatically for every host built with `os_config_live`, and it does nothing
  until `enable` is set.
- New `docs/services/attic-pull.md`, and a link from `docs/README.md`.
- New checks `attic-pull` (evaluation) and `attic-pull-vm` (two-node NixOS VM)
  in `flake.nix`.
- Follow-up outside this repository: workloads replaces its own module with this
  one in every compute hostconf, keeps only the glue from tfvars and the
  per-host age secret, and re-pins elastinix in each stack flake.
