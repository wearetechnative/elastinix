---
# elastinix-h1qi
title: 'badgersbay module: assertions on the secret files at evaluation'
status: completed
type: task
priority: high
created_at: 2026-09-16T15:52:07Z
updated_at: 2026-09-16T16:55:15Z
parent: elastinix-l16a
---

A secret that is missing, undeclared or unreadable currently produces a service
that fails at start: the server exits on `FileNotFoundError` or
`PermissionError` and systemd restarts it every ten seconds. The deploy itself
reports success. Move what can be known at evaluation to evaluation.

## What evaluation can know

    the path is a nix store path       catchable - and a boundary violation
    the path is under age.secretsDir
      but no age.secrets entry
      produces it                      catchable - the secret is never written
    the secret is owned by root at
      0400 while the service runs as
      badgersbay                       catchable - the file exists, unreadable

## What it cannot

Whether `/run/agenix/badgersbay-tokens` exists: it is decrypted at activation,
long after evaluation, and `builtins.pathExists` on a deploy host says nothing
about the target. Asserting on it would fail every remote build. The
assertions therefore check the declarations, not the filesystem - and the docs
say so rather than promising more than they deliver.

## Scope

- No secret file may be a nix store path. `pkgs.writeText` and a path literal
  both land world-readable in the store; this is the epic's hard boundary, and
  it is checkable.
- A path under `config.age.secretsDir` must correspond to a declared
  `age.secrets` entry.
- A declared secret that cannot be read by `user`/`group` fails, naming the
  `owner` and `mode` to set. agenix defaults to root:root 0400, so this is the
  common case, not the exotic one.
- Skip the agenix-specific checks when the agenix module is not imported.

## Todo

- [ ] Store path assertion for all three secret options
- [ ] Undeclared agenix path assertion
- [ ] Unreadable-by-service assertion
- [ ] Evaluate configurations that must fail, and confirm they fail with the
      intended message rather than passing silently
