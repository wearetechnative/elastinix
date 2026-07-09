## Context

**Getest gedrag (compute1-nonprod, t3.small, 1.9GB RAM, geen swap):**
- `vulnix --from-file` zonder cache: OOM kill — vulnix laadt ~1GB RAM voor initiële NVD database download + parse + ZODB reindex
- `vulnix --from-file` met 1.5GB swapfile: succesvol in ~2 minuten, 146MB Data.fs aangemaakt, exit 2 (kwetsbaarheden gevonden)
- Tweede run (cache aanwezig, `modified` feed): 1.95 seconden, geen swap nodig
- Disk beschikbaar: 8.6GB vrij op compute1-nonprod

**Hoe vulnix memory gebruikt:**
- Eerste run: download 6 jaar NVD JSON archives van GitHub → parse → schrijf naar ZODB → `reindex()` bouwt `by_product` BTree over alle CVEs → ~1GB RAM piek
- Volgende runs: `relevant_archives()` retourneert alleen `"modified"` feed als laatste update < 7 dagen → veel kleiner, ZODB doet lazy loading

**Huidige situatie:**
- Service genereert zelf packages.json via `nix-store -qR /run/current-system` (Python script)
- Cache staat in `/var/lib/sbom/cache` (gemengd met SBOM output)
- Geen bootstrap-mechanisme; faalt stil op t3.small

## Goals / Non-Goals

**Goals:**
- Service werkt op t3.small zonder permanente swap
- packages.json aangeleverd door deploy-wrapper, niet meer door service zelf gegenereerd
- Swapfile alleen aangemaakt bij eerste run (lege cache), daarna nooit meer
- Cache persistent en gescheiden van SBOM output

**Non-Goals:**
- Aanpassen van de vulnix binary of ZODB-implementatie
- Ondersteuning voor hosts zonder internet (NVD mirror configuratie is uit scope)
- Automatisch updaten van packages.json zonder deploy (dat is de verantwoordelijkheid van de deploy-wrapper)

## Decisions

### Decision 1: Bootstrap detectie op basis van Data.fs grootte

**Keuze:** Bootstrap-modus actief als `/var/lib/vulnix-cache/Data.fs` niet bestaat of kleiner dan 1MB is.

**Rationale:**
- Een gevulde ZODB cache is altijd > 100MB (getest: 146MB)
- Een lege of gecorrumpeerde ZODB is < 200 bytes
- Eenvoudige check, geen externe dependencies

**Alternatieven overwogen:**
- Timestamp check: complexer, minder betrouwbaar na handmatige delete
- Aparte flag file: extra state om bij te houden

### Decision 2: Swapfile op /var/lib/vulnix-cache/swap (niet /tmp)

**Keuze:** Swapfile aanmaken op `/var/lib/vulnix-cache/swap`.

**Rationale:**
- `/tmp` kan tmpfs zijn (RAM-based) — zou geen echte swap geven
- `/var/lib/vulnix-cache` is altijd op de root disk (persistent EBS)
- Swapfile staat naast de cache — logisch gegroepeerd

**Alternatieven overwogen:**
- `/swapfile` in root: werkt maar minder overzichtelijk
- `/tmp/vulnix-swap`: risico op tmpfs

### Decision 3: Disk-check vooraf (minimaal 2GB vrij)

**Keuze:** Script checkt `df` output vóór aanmaken swapfile; bij < 2GB vrij: skip bootstrap, log waarschuwing.

**Rationale:**
- Swapfile (1.5GB) + Data.fs (~150MB) = ~1.65GB totaal nodig
- Voorkomen dat schijf volloopt op productie hosts
- 2GB marge is voldoende buffer

### Decision 4: ExecStopPost ruimt swapfile op

**Keuze:** `ExecStopPost` script: swapoff + rm -f op de swapfile locatie.

**Rationale:**
- Als service crasht tijdens bootstrap blijft swapfile actief
- systemd voert ExecStopPost altijd uit, ook bij failure
- Idempotent (swapoff faalt niet als swap al inactief is)

### Decision 5: Cache naar /var/lib/vulnix-cache/

**Keuze:** Verplaats cache van `/var/lib/sbom/cache` naar `/var/lib/vulnix-cache/`.

**Rationale:**
- `/var/lib/sbom/` is voor SBOM output (packages.json, system.json)
- `/var/lib/vulnix-cache/` is voor vulnix interne state (NVD database)
- Scheiding maakt backup/restore eenvoudiger
- `ReadWritePaths` in serviceConfig kan per directory geconfigureerd worden

## Risks / Trade-offs

- **packages.json niet aanwezig bij eerste scan** → service logt fout en stopt (exit 0). Geen crashloop. Mitigatie: deploy-wrapper upload altijd packages.json vóór eerste systemd timer trigger.
- **Bootstrap crasht halverwege** → ZODB `reinit()` herstelt automatisch bij volgende run. Swapfile wordt opgeruimd door ExecStopPost.
- **Disk vol check passeert maar disk loopt vol** → onwaarschijnlijk (check vooraf + 350MB marge). Bij disk-vol faalt `dd` met duidelijke foutmelding in journal.
- **Tweede host met meer services** → meer packages, grotere scan. Getest op 1119 packages (t3.small). Verwacht dat grotere instances (t3a.large, t3a.medium) voldoende RAM hebben zonder swap.
