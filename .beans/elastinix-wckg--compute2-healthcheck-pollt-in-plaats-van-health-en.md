---
# elastinix-wckg
title: 'compute2: healthcheck pollt /  in plaats van /health en meet daardoor niets'
status: todo
type: bug
priority: normal
tags:
    - badgersbay
    - monitoring
created_at: 2026-09-15T20:31:30Z
updated_at: 2026-09-15T20:31:30Z
---

Iets pollt op compute2-prod elke 30 seconden het badgersbay-dashboard op `/`
in plaats van op `/health`, zonder inloggegevens:

    20:25:22  127.0.0.1 - "GET / HTTP/1.1" 401
    20:25:52  127.0.0.1 - "GET / HTTP/1.1" 401
    20:26:22  127.0.0.1 - "GET / HTTP/1.1" 401

## Waarom dit fout is

`/` is het dashboard en zit achter basic auth. De poller heeft geen
inloggegevens, dus hij krijgt altijd 401 — ongeacht of de dienst gezond is.
Een 401 komt er ook als de opslag onbereikbaar is of de compliance-cache leeg.
De check meet dus niets en vult ondertussen het log.

`/health` is het endpoint dat hiervoor bestaat: geen authenticatie, en het
antwoordt met status, uptime, opslagtoegankelijkheid en rapportstatistieken.
Sinds badgersbay b4ae8ab kloppen die cijfers ook op een compliance-installatie.

## Uit te zoeken

De bron is nog niet gevonden:

- `badgersbay.timer` is `OnCalendar=hourly`, dus die is het niet
- geen healthcheck-unit gevonden in `systemctl list-units`
- `service-badgersbay.nix` bevat geen healthcheck-configuratie
- compute2's `hostconf.nix` noemt `healthchecks` nergens

Kandidaten: `nixos-healthchecks` (input van elastinix), een blackbox-exporter,
of iets in de monitoring-stack. Verzoek komt van 127.0.0.1, dus het draait op de
host zelf.

## Op te lossen

1. De poller vinden
2. Richten op `http://localhost:9117/health`, verwachte status 200
3. Overwegen om op de inhoud te controleren in plaats van alleen de statuscode:
   `storage.accessible` is de zinnige indicator, want de server antwoordt ook
   met 200 als de opslaglocatie weg is
