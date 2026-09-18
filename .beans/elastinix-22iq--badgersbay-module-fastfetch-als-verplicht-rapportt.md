---
# elastinix-22iq
title: 'badgersbay module: fastfetch as the required report type'
status: completed
type: task
priority: high
tags:
    - badgersbay
    - nixos
created_at: 2026-09-15T19:30:23Z
updated_at: 2026-09-15T19:31:49Z
parent: elastinix-l16a
---

From 844176c badgersbay no longer accepts `neofetch` as a report type. The
module default at `service-badgersbay.nix:79` still sends it.

These two belong in one commit, because either half alone breaks in both
directions:

    lock bump only    server rejects 'neofetch', module still sends it
    default fix only  module sends 'fastfetch', old server does not know it

Both produce the same result: every system recorded as incomplete.

## Scope

1. `flake.lock`: badgersbay from 264abe4 to 844176c
2. `service-badgersbay.nix:79`: `- neofetch` becomes `- fastfetch`

Nothing more. Restructuring into a `settings` option and adding
`assetRegisterFile` stay in the parent epic.

## Note

`nix flake lock --update-input badgersbay` initially reported no change: nix
served a cached fetch within `tarball-ttl`. `--refresh` moved it. After any bump,
check that the revision actually changed.
