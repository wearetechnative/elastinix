---
# elastinix-22iq
title: 'badgersbay-module: fastfetch als verplicht rapporttype'
status: todo
type: task
priority: high
tags:
    - badgersbay
    - nixos
created_at: 2026-09-15T19:30:23Z
updated_at: 2026-09-15T19:30:23Z
parent: elastinix-l16a
---

Badgersbay accepteert vanaf 844176c geen `neofetch` meer als rapporttype. De
module-default in `service-badgersbay.nix:79` stuurt het nog wel.

Deze twee moeten in één commit, want los van elkaar breekt het in beide
richtingen:

    alleen lock bumpen    server kent 'neofetch' niet, module stuurt het nog
    alleen default fixen  module stuurt 'fastfetch', oude server kent het niet

Beide geven hetzelfde resultaat: elk systeem wordt als Incomplete geboekt.

## Scope

1. `flake.lock`: badgersbay van 264abe4 naar 844176c
2. `service-badgersbay.nix:79`: `- neofetch` wordt `- fastfetch`

Meer niet. De herstructurering naar een `settings`-optie en het toevoegen van
`assetRegisterFile` blijven in het bovenliggende epic.

## Let op

`nix flake lock --update-input badgersbay` gaf aanvankelijk geen wijziging: nix
serveerde een gecachete fetch binnen `tarball-ttl`. Met `--refresh` schoof de
rev wel mee. Controleer na een bump altijd of de rev daadwerkelijk verandert.
