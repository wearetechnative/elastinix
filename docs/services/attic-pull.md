# Attic Pull Consumer

The Attic pull service (`elastinix.services.attic_pull`) makes a host pull from a private [Attic](https://github.com/zhaofengli/attic) binary cache, such as one served by [`elastinix.services.attic`](attic.md). It configures the Nix daemon only and runs nothing of its own.

## Why a module

Three Nix settings have to change together, and a mistake in any of them doesn't raise an error. Deploys just get slower, because the host builds what it could have fetched:

| Mistake                                 | Effect                                            |
|-----------------------------------------|---------------------------------------------------|
| netrc without the substituter           | Credentials for a cache Nix never asks            |
| substituter without the trusted key     | Nix refuses every path the cache serves           |
| bare `substituters = [ … ]` assignment  | `cache.nixos.org` is dropped                      |

The module sets all three, and refuses at evaluation time a configuration that is incomplete or malformed.

## Configuration

### Options

| Option       | Type           | Default | Description                                                          |
|--------------|----------------|---------|----------------------------------------------------------------------|
| `enable`     | boolean        | `false` | Pull from the cache                                                  |
| `endpoint`   | null or string | `null`  | Attic server base URL, `http://` or `https://`, without the cache    |
| `cache`      | null or string | `null`  | Cache name; the substituter becomes `<endpoint>/<cache>`             |
| `public_key` | null or string | `null`  | The cache's public key, `<name>:<base64>` as `attic cache info` shows |
| `netrc_file` | null or string | `null`  | Absolute path to the decrypted netrc holding the pull token          |

The module takes no `tfvars`. The deployment fills the options from wherever it keeps them.

### Example with agenix

```nix
{ config, ... }:
{
  age.secrets.attic-pull = {
    file = ./secrets/attic-pull.age;
    owner = "root";  # read by the nix daemon, which runs as root
    group = "root";
    mode = "400";
  };

  elastinix.services.attic_pull = {
    enable = true;
    endpoint = "https://attic.example.com";
    cache = "infra";
    public_key = "infra:Z/e9fATMRoLBa6kHVJxHJ98PR8fqeVr99TOWnqkAnYc=";
    netrc_file = config.age.secrets.attic-pull.path;
  };
}
```

`netrc_file` is a string, not a Nix path, so the secret is never copied into the Nix store. The module doesn't depend on agenix: any mechanism that puts a readable file at an absolute path works.

### The netrc

The secret holds a **complete netrc**, not a bare token, because `nix.settings.netrc-file` points straight at it:

```
machine attic.example.com
password <JWT>
```

`machine` must be the host part of `endpoint`, without the scheme or port. The module can't check this without reading the secret. Create a pull-only token on the server and encrypt it non-interactively:

```bash
atticd-atticadm make-token --sub <host> --validity 1y --pull infra
printf 'machine attic.example.com\npassword %s\n' "$TOKEN" | agenix -e secrets/attic-pull.age
```

## What the module sets

```nix
nix.settings = {
  substituters        = lib.mkAfter [ "<endpoint>/<cache>" ];
  trusted-public-keys = lib.mkAfter [ public_key ];
  netrc-file          = netrc_file;
};
```

- **Order**: `mkAfter` keeps `cache.nixos.org` and anything else already configured, and puts the Attic cache after them. Attic advertises priority 41 against upstream's 40, so public paths keep coming from upstream and the Attic cache serves only what you built yourself.
- **Trailing slash**: `https://attic.example.com/` and `https://attic.example.com` give the same substituter.
- **`netrc-file` is a single value**: another module that sets it too causes a conflict at evaluation time, not a silent override.
- **Trust**: the host accepts **any** store path the cache's key signs. Push access to the cache is therefore what has to be guarded, not pull access.

## Evaluation errors

| Message contains                                 | Cause                                                              |
|--------------------------------------------------|--------------------------------------------------------------------|
| `attic_pull.<option> is not set`                 | Option missing or empty while `enable = true`                      |
| `endpoint must start with http:// or https://`   | Scheme missing from `endpoint`                                     |
| `is not a valid Attic cache name`                | Name not `[A-Za-z0-9][A-Za-z0-9-_+]{0,49}` (Attic's own rule)      |
| `public_key must have the form`                  | Not `<name>:<base64 of 32 bytes>`                                  |
| `public_key is a secret key`                     | The 64-byte secret key was pasted; treat it as leaked              |
| `netrc_file must be an absolute path`            | Relative path given                                                |

## Verification

On the host:

```bash
grep -E '^(substituters|trusted-public-keys|netrc-file)' /etc/nix/nix.conf
curl -sf --netrc-file /run/agenix/attic-pull https://attic.example.com/infra/nix-cache-info
```

The second command prints the cache's `nix-cache-info`. A `401` means the token is invalid or `machine` doesn't match the host.

## Testing

An evaluation check covers what the module renders and every assertion, in both directions. It also evaluates the agenix example above:

```bash
nix build .#checks.x86_64-linux.attic-pull -L
```

A two-node NixOS VM test runs an Attic server with a private cache and a client with this module enabled. The client can't substitute a path while its netrc is missing, and substitutes it once the netrc holds a pull token:

```bash
nix build .#checks.x86_64-linux.attic-pull-vm -L
```

## Troubleshooting

| Symptom                                                 | Cause                                                        |
|---------------------------------------------------------|--------------------------------------------------------------|
| `HTTP error 401` for `.../nix-cache-info`               | netrc missing, token expired, or `machine` doesn't match     |
| `no substituter that can build it` for your own paths   | Path not pushed, or the cache's key differs from `public_key`|
| Public paths suddenly come from Attic                   | Something set `substituters` without `mkAfter`/upstream      |
