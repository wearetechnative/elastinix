# Spec Delta

## Purpose

Defines what the Attic pull-consumer module configures on a host so that its
Nix pulls from a private Attic cache: which Nix settings it changes, how the
pull credential reaches Nix without entering the Nix store, and which
configurations it refuses to evaluate.

## ADDED Requirements

### Requirement: Option set

The module SHALL provide `elastinix.services.attic_pull` with these options:

| Option       | Type           | Default |
|--------------|----------------|---------|
| `enable`     | boolean        | `false` |
| `endpoint`   | null or string | `null`  |
| `cache`      | null or string | `null`  |
| `public_key` | null or string | `null`  |
| `netrc_file` | null or string | `null`  |

The module SHALL NOT read `tfvars` or any other deployment-specific argument.
While `enable` is `false`, it SHALL NOT change the host's configuration.

#### Scenario: Disabled module changes nothing

- **WHEN** a host imports the module without setting `enable`
- **THEN** its `nix.settings.substituters`, `nix.settings.trusted-public-keys`
  and `nix.settings.netrc-file` are the same as they would be without the module

#### Scenario: No tfvars required

- **WHEN** a host is evaluated with the module enabled and every option set,
  and no `tfvars` argument is present
- **THEN** evaluation succeeds

### Requirement: Add the cache without displacing existing substituters

When enabled, the module SHALL append `<endpoint>/<cache>` to
`nix.settings.substituters` and `public_key` to
`nix.settings.trusted-public-keys`. Values set elsewhere, including the NixOS
default `https://cache.nixos.org/` and its key, SHALL be kept and SHALL come
before the Attic cache. A trailing `/` on `endpoint` SHALL NOT produce a double
slash in the substituter URL.

#### Scenario: Upstream cache is kept

- **WHEN** the module is enabled with `endpoint = "https://attic.example.com"`
  and `cache = "infra"`
- **THEN** `nix.settings.substituters` contains `https://cache.nixos.org/`
  followed by `https://attic.example.com/infra`
- **AND** `nix.settings.trusted-public-keys` contains the `cache.nixos.org-1`
  key followed by `public_key`

#### Scenario: Trailing slash on the endpoint

- **WHEN** `endpoint = "https://attic.example.com/"` and `cache = "infra"`
- **THEN** the substituter is `https://attic.example.com/infra`

### Requirement: Take the pull credential from a file outside the Nix store

When enabled, the module SHALL set `nix.settings.netrc-file` to `netrc_file`.
`netrc_file` SHALL be the path of a netrc that has already been decrypted and
names the endpoint's host as `machine`, with the Attic pull token as
`password`. The module SHALL NOT decrypt, create or copy the file, and SHALL NOT
place its contents in the Nix store. The documentation SHALL show the agenix
secret that provides this file: owned by `root`, mode `400`, because the Nix
daemon reads it as root.

#### Scenario: netrc-file points at the given path

- **WHEN** `netrc_file = "/run/agenix/attic-pull"`
- **THEN** `nix.settings.netrc-file` is `/run/agenix/attic-pull`

#### Scenario: A private cache is pulled with the credential

- **WHEN** a host has the module enabled for a private cache, and a store path
  exists only in that cache
- **AND** the file at `netrc_file` holds a valid pull token for the endpoint's
  host
- **THEN** realising that store path on the host substitutes it from the cache

#### Scenario: Without the credential the private cache is not usable

- **WHEN** the same host realises the same store path while the file at
  `netrc_file` does not exist
- **THEN** the path is not substituted from the cache

### Requirement: Refuse incomplete or malformed configurations

When enabled, the module SHALL fail evaluation with an assertion naming the
option at fault if any of the following hold:

- `endpoint`, `cache`, `public_key` or `netrc_file` is `null` or empty
- `endpoint` does not start with `http://` or `https://`
- `cache` is not a valid Attic cache name: an ASCII letter or digit, followed
  by at most 49 characters from letters, digits, `-`, `_` and `+`
- `public_key` is not of the form `<name>:<base64 of 32 bytes>`
- `netrc_file` is not an absolute path

A `public_key` that has the shape of a Nix secret key, that is
`<name>:<base64 of 64 bytes>`, SHALL be rejected with a message that says it is
the secret key. The message SHALL warn that the value would otherwise be
written into the world-readable Nix store.

#### Scenario: Missing value

- **WHEN** the module is enabled and `cache` is not set
- **THEN** evaluation fails with an assertion naming
  `elastinix.services.attic_pull.cache`

#### Scenario: Secret key given as public key

- **WHEN** `public_key` is a 64-byte Nix secret key
- **THEN** evaluation fails with an assertion stating that it is a secret key

#### Scenario: Relative netrc path

- **WHEN** `netrc_file = "secrets/attic-pull"`
- **THEN** evaluation fails with an assertion naming
  `elastinix.services.attic_pull.netrc_file`

### Requirement: No service of its own

The module SHALL NOT add a systemd unit. It configures only the Nix daemon's
settings, so the systemd hardening convention for elastinix services does not
apply to it.

#### Scenario: No unit added

- **WHEN** the module is enabled
- **THEN** the set of systemd services is the same as with the module disabled
