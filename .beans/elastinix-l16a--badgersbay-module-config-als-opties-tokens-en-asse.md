---
# elastinix-l16a
title: 'badgersbay-module: config als opties, tokens en assetregister via agenix'
status: todo
type: epic
priority: high
tags:
    - badgersbay
    - nixos
    - agenix
created_at: 2026-09-15T16:24:06Z
updated_at: 2026-09-15T16:24:06Z
---

`service-badgersbay.nix` beheert de badgersbay-configuratie nu half. De module
moet de vorm bezitten; agenix bezit de waarden.

## Huidige situatie

    configFile            types.path, default = writeText met een
                          hardgecodeerde heredoc
    tokenFile             types.path, wijst naar een agenix-secret
    dashboardPasswordFile types.path, wijst naar een agenix-secret

Drie problemen.

**De configuratie is een string, geen opties.** Het compliance-blok staat
letterlijk in de module:

    compliance:
      enabled: true
      audit_months: [3, 9]
      required_reports:
        mandatory:
          - neofetch
          - lynis
        one_of: []

Wie de auditmaanden wil wijzigen moet `configFile` in zijn geheel overschrijven
en daarmee de rest van de generatie kwijtraken. Er is geen `mkOption` voor iets
binnen het blok.

Dat is geen theorie. `technative-awsaccounts-workloads`, compute2, doet precies
dat:

    configFile = config.age.secrets.badgersbay-config.path;

Gevolg: toen de moduledefault van `neofetch` naar `fastfetch` ging
(elastinix-22iq), bereikte die wijziging de productiehost niet. Het echte
configuratiebestand zit in een agenix-secret dat apart bijgewerkt moest worden.
Een module die alleen een heel bestand als optie aanbiedt, kan zijn eigen
defaults niet meer uitrollen zodra iemand iets wil afwijken.

**Die default is inmiddels onjuist.** `mandatory: [neofetch, lynis]` klopt niet
meer: badgersbay stapt over op fastfetch (change `use-fastfetch-system-info`).
Een host die vandaag met de module-default uitrolt, markeert elk Linux-systeem
permanent als incompleet. Dit is de dringendste regel in dit epic.

**Er komt een derde bestand bij.** `asset-register-identity` voegt `assets.csv`
toe: het asset-register, geëxporteerd uit de ISO-rapportagesheet. Het bevat
volledige namen gekoppeld aan hardware-serienummers, dus het hoort op het
agenix-spoor, niet in de repo.

## Scope

1. `settings` als gestructureerde optie, gerenderd naar YAML, in plaats van een
   heredoc. Minimaal `compliance.enabled`, `audit_months`, `grace_weeks`,
   `required_reports`, en de per-platformklasse-eisen die badgersbay krijgt.
2. Default naar `fastfetch` in plaats van `neofetch`.
3. `assetRegisterFile` toevoegen naast `tokenFile` en
   `dashboardPasswordFile`, met hetzelfde agenix-patroon.
4. Assertions: ontbrekende of onleesbare secretbestanden falen bij evaluatie,
   niet pas bij het starten van de service.
5. `docs/services/badgersbay.md` bijwerken.

## Grens: geheimen gaan niet in de nix-store

`pkgs.writeText` schrijft naar de nix-store, en die is wereldleesbaar. Tokens
en het dashboardwachtwoord mogen daar dus nooit als waarde in terechtkomen —
ook niet via een `tokens = [ ... ]`-optie die vriendelijk oogt.

De verdeling die dit epic hanteert:

    module bezit    de structuur: welke sleutels, welke vorm, welke defaults
    agenix bezit    de waarden: tokens, wachtwoord, assetregister

Dus `settings` wordt wél een echte optie, want daar staan geen geheimen in.
`tokenFile`, `dashboardPasswordFile` en het nieuwe `assetRegisterFile` blijven
paden. Wil de module ooit de inhoud van een secret samenstellen, dan gebeurt
dat bij activatie uit een agenix-bestand, nooit via de store.

## Afhankelijkheden

- badgersbay `use-fastfetch-system-info` — bepaalt de juiste default
- badgersbay `asset-register-identity` — introduceert `assets.csv`
- badgersbay `register-administration` — bevat de open keuze tussen agenix en
  dashboard-upload voor het register; dit epic gaat uit van agenix
