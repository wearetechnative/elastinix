## Why

Badgersbay measures compliance against an asset register: the list of systems
expected to report, exported from the ISO compliance sheet. Without one the
dashboard can show what arrived but never which systems are missing, and both
its views say so plainly:

    No asset register configured

The register pairs employee names with hardware serials, so it belongs on the
same track as the tokens and the dashboard password - an agenix secret,
encrypted at rest and delivered to the host - rather than in a repository or in
the configuration the module generates.

The secret is already in place. `technative-awsaccounts-workloads` commit
1ac4467 added `badgersbay-assets.age` and its `age.secrets` block for compute2,
with a comment recording that it waits on this option. Nothing consumes it yet.

## What Changes

- **`assetRegisterFile`**, a path option alongside `tokenFile` and
  `dashboardPasswordFile`, following the same agenix pattern.
- The service passes it to badgersbay as `--asset-register`, which takes
  precedence over anything the configuration file names.
- Optional: a host that does not set it runs as it does today, without a
  register.

## Capabilities

### New Capabilities
- `badgersbay-service`: what the module configures and how the server is
  started

## Impact

- No change for a host that does not set the option.
- A host that sets it gains the round and fleet views. It also gains a hard
  dependency: badgersbay refuses to start on a register it cannot trust - a
  duplicate active serial, an unknown platform class, an unparseable date -
  because a compliance figure built on one cannot be trusted either.

## Non-goals

- Restructuring `configFile` into a `settings` option. That is the other half
  of `elastinix-l16a` and blocks nothing: compute2 overrides `configFile`
  wholesale with its own secret, so a structured option would not reach it
  anyway. Passing the register as an argument avoids touching that secret at
  all.
