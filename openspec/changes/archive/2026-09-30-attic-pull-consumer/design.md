# Design

## Context

The workloads module (`workloads.atticPull`) does three things. It declares its
own `age.secrets.attic-pull` from a `secretFile` option. It reads
`attic_endpoint`, `attic_cache` and `attic_public_key` from `tfvars`. It sets
the three `nix.settings` keys. Every host built with `os_config_live` imports
all of `modules/nixos/services` through `import-tree`, so a new file there is
available fleet-wide as soon as elastinix is re-pinned. It stays inert until
enabled.

The elastinix attic server module already solves the same secret problem for
atticd: `environment_file` is a plain path string, and the host declares the
agenix secret itself.

## Goals / Non-Goals

**Goals:**

- One definition of "pull from an Attic cache" that any elastinix host can use.
- Every configuration mistake that would otherwise only show up as a slower
  deploy is caught at evaluation time.
- Tests that prove a host actually substitutes from a private cache, not only
  that the settings render.

**Non-Goals:**

- Pushing to the cache, or the workstation-side deploy wrapper
  (`packages_listing_deploy_wrapper.nix`) and `attic-reconcile.sh`. Both stay
  in workloads.
- Several caches per host. Nothing needs this today (see D6).
- Changing the workloads repository. That is a follow-up there.

## Decisions

### D1. Namespace `elastinix.services.attic_pull`, snake_case options

The bean suggested `elastinix.attic.pull`. Every elastinix module lives under
`elastinix.services.*` or `elastinix.programs.*`, so a new top-level `attic`
namespace would be the only one of its kind. `elastinix.services.attic.pull`
would sit under the *server's* option set, next to the server's own `enable`,
and a reader would take it for a server setting. `attic_pull`, next to `attic`,
reads as its sibling. Options use snake_case (`public_key`, `netrc_file`) to
match `environment_file` and `s3_bucket` in the server module.

### D2. `netrc_file` is a path string, not an age file

*Alternative:* take the `.age` file and declare `age.secrets` inside the module,
as workloads does. That would tie the module to agenix and fix the secret's name
and path. It would also mean two modules could both claim
`age.secrets.attic-pull`. With a path string, the host keeps its secret
declaration, as it already does for `elastinix.services.attic.environment_file`.
The documentation carries the matching agenix snippet (`owner = "root"`,
`mode = "400"`). The type is `str`, not `path`: a `path` would copy a local
file into the Nix store at evaluation time, which is exactly the leak this
option exists to avoid.

### D3. Values default to `null`; assertions do the checking

If the options were plain `str` without defaults, NixOS would fail with
"The option … is used but not defined". That message doesn't say what the value
should look like. With `nullOr str` and `null` defaults, the module's own
assertions can say what is missing and in what form. All assertions are guarded
by `enable`, so a host that doesn't use the module never trips them.

### D4. `mkAfter` for the lists, a plain definition for `netrc-file`

`substituters` and `trusted-public-keys` are lists that merge, so `mkAfter`
appends the cache after `cache.nixos.org`. Nix tries substituters in priority
order, and Attic reports priority 41 against upstream's 40, so public paths
keep coming from upstream. `netrc-file` is a single value. The module defines
it at normal priority, so another module that also sets it causes a conflict at
evaluation time instead of one value silently overriding the other.

### D5. Validate the public key's shape, and name the secret-key mistake

A Nix public key is `<name>:` followed by 44 base64 characters (32 bytes). A
secret key has the same prefix followed by 88 characters (64 bytes), which makes
it easy to paste by mistake. Pasting the secret key would write it into the
world-readable Nix store *and* be refused by Nix as a trusted key. The assertion
checks for this shape specifically and says so. The cache-name check uses
Attic's own rule (`^[A-Za-z0-9][A-Za-z0-9-_+]{0,49}$`, from `attic/src/cache.rs`).

### D6. A single cache, explicit `enable`

Workloads enables the module implicitly when `secretFile` is set. Elastinix
modules have an explicit `enable`, and the glue in workloads can still write
`enable = secretFile != null`. One cache per host covers every current
consumer. An `instances` attrset would add complexity with no current user,
and can be added later without breaking the single-cache options.

### D7. Two checks: evaluation and a two-node VM

- `attic-pull` (evaluation, like `attic-garbage-collection`): covers rendering,
  ordering, trailing-slash handling, the disabled no-op, and each assertion.
  Every assertion is checked in both directions: the valid configuration
  passes, and each broken variant fails with its own message.
- `attic-pull-vm`: a `server` node runs upstream `services.atticd` with local
  storage and SQLite. The server module isn't under test, and its S3 backend
  has no endpoint inside a VM. A `client` node enables `attic_pull`.

  The client's `nix.conf` is built before the VM boots, but Attic generates a
  cache's keypair when the cache is created. The test therefore creates the
  cache through `POST /_api/v1/cache-config/<cache>` with
  `KeypairConfig::Keypair`, which the server API accepts even though the CLI
  doesn't expose it. It uses a throwaway keypair committed in the test, so the
  client can trust a key known at build time. The cache is private.

  The server pushes a path that only exists at runtime. The client first fails
  to realise it without a netrc, then realises it after the netrc is written.
  That proves the substituter, the trusted key and the credential all take
  effect.

## Risks / Trade-offs

- [Risk] The netrc's `machine` must match the endpoint's host, and the module
  can't check this without reading the secret. → The documentation states it,
  and the workloads secret is already in this form.
- [Risk] The negative-lookup cache from the first, credential-less attempt in the
  VM test could mask the second attempt. → The test clears the Nix cache
  directory between the two attempts.
- [Trade-off] Trusting `public_key` means the host accepts any path the cache
  signs, so push access to the cache is what needs guarding. → Documented. This
  is inherent to any trusted substituter.

## Migration Plan

Nothing changes for existing hosts: the module is inert until enabled. The
workloads follow-up replaces `workloads.atticPull` host by host with
`elastinix.services.attic_pull`. Its values come from the same tfvars keys, and
`netrc_file = config.age.secrets.attic-pull.path`. To roll back, revert the
hostconf to the workloads module. No state is involved.
