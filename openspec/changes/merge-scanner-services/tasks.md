## 1. Nieuwe gecombineerde module

- [x] 1.1 Maak `modules/nixos/services/service-vulnerability-scan-central.nix` met `elastinix.services.vulnerability-scan-central` namespace
- [x] 1.2 Implementeer `hostType` submodule met `name`, `url` en `enableDockerScan` (default `false`) opties
- [x] 1.3 Implementeer `enable`, `hosts` en `interval` (default `"weekly"`) opties op service-niveau
- [x] 1.4 Schrijf scan script: voor elke host fetch `packages.json` en run vulnix; handel exit code 2 af zonder service failure
- [x] 1.5 Voeg per-host trivy-blok toe in scan script: alleen uitvoeren als `enableDockerScan = true`; fetch `docker-images.json`, scan elke image
- [x] 1.6 Maak directories aan via `systemd.tmpfiles.rules`: `/var/lib/vulnix`, `/var/lib/vulnix-cache`, `/var/lib/trivy`
- [x] 1.7 Pas systemd hardening toe: `ReadWritePaths`, `PrivateTmp`, `ProtectSystem`, `NoNewPrivileges`, `RestrictAddressFamilies`

## 2. Verwijder oude modules

- [x] 2.1 Verwijder `modules/nixos/services/service-vulnix-scan-central.nix`
- [x] 2.2 Verwijder `modules/nixos/services/service-trivy-scan-central.nix`

## 3. Documentatie

- [x] 3.1 Maak `docs/services/vulnerability-scan-central.md` met configuratie-opties, voorbeeldconfig en migratiegids
- [x] 3.2 Update `docs/services/vulnix-scan-central.md` naar deprecated notice met verwijzing naar `vulnerability-scan-central.md`
- [x] 3.3 Update `docs/services/trivy-scan-central.md` naar deprecated notice met verwijzing naar `vulnerability-scan-central.md`
- [x] 3.4 Update `docs/README.md`: vervang `vulnix-scan-central` en `trivy-scan-central` door `vulnerability-scan-central` onder Security Services

## 4. vulnixCacheDir optie

- [x] 4.1 Voeg `vulnixCacheDir` string optie toe aan module (default `"/var/lib/vulnix-cache"`)
- [x] 4.2 Gebruik `cfg.vulnixCacheDir` in scan script (`VULNIX_CACHE`), `systemd.tmpfiles.rules` en `ReadWritePaths`
- [x] 4.3 Voeg `trivyCacheDir` string optie toe aan module (default `"/var/lib/trivy-cache"`)
- [x] 4.4 Geef `--cache-dir "$TRIVY_CACHE"` mee aan trivy; voeg pad toe aan `systemd.tmpfiles.rules` en `ReadWritePaths`
- [x] 4.5 Update `docs/services/vulnerability-scan-central.md` met `vulnixCacheDir` en `trivyCacheDir` opties

## 5. Robuustheid scan script

- [x] 5.1 Vervang `set -euo pipefail` door `set -u` — script stopt niet meer bij individuele fouten
- [x] 5.2 Vervang `| while read` door `while read < <(...)` — process substitution voorkomt pipe-fout bij falende jq
- [x] 5.3 Voeg `ERRORS` teller toe — telt waarschuwingen, gerapporteerd aan einde; service eindigt altijd met `exit 0`
- [x] 5.4 Bijhoud exitcode per tool apart (`VEXIT`, `TEXIT`) in plaats van globale `EXIT` variabele

## 6. Verificatie

- [x] 6.1 `nix flake check --no-build` — geen evaluatiefouten
- [x] 6.2 Verifieer dat `vulnerability-prometheus-exporter` nog correct evalueert (output-paden ongewijzigd)
- [x] 6.3 Update bean `elastinix-m7qf` status naar `completed`

## 7. WARNINGS teller

- [x] 7.1 Voeg `WARNINGS=0` toe aan script naast `ERRORS=0`
- [x] 7.2 Incrementeer `WARNINGS` bij curl-fout voor `packages.json` (vulnix)
- [x] 7.3 Incrementeer `WARNINGS` bij curl-fout voor `docker-images.json` (trivy)
- [x] 7.4 Update laatste echo naar `"Central vulnerability scan complete. Warnings: $WARNINGS, Errors: $ERRORS"`
