## 1. Verwijder generatePackagesJson

- [x] 1.1 Verwijder de `generatePackagesJson` let-binding (regels 6-22) uit `service-vulnix-scan.nix`
- [x] 1.2 Verwijder de aanroep van `${generatePackagesJson}` uit het service script
- [x] 1.3 Vervang de hardcoded `/var/lib/sbom/packages.json` schrijflocatie door een read van datzelfde pad

## 2. Voeg packages.json check toe

- [ ] 2.1 Voeg aan het begin van het service script een check toe: als `/var/lib/sbom/packages.json` niet bestaat, log waarschuwing en exit 0
- [ ] 2.2 Voeg `ReadOnlyPaths = [ "/var/lib/sbom" ]` toe aan serviceConfig (naast bestaande ReadWritePaths)

## 3. Verplaats cache naar /var/lib/vulnix-cache

- [ ] 3.1 Verander `--cache-dir /var/lib/sbom/cache` naar `--cache-dir /var/lib/vulnix-cache` in het vulnix-commando
- [ ] 3.2 Voeg `"d /var/lib/vulnix-cache 0755 root root -"` toe aan `systemd.tmpfiles.rules`
- [ ] 3.3 Voeg `/var/lib/vulnix-cache` toe aan `ReadWritePaths` in serviceConfig

## 4. Implementeer bootstrap-mechanisme

- [ ] 4.1 Voeg disk-check toe vóór bootstrap: bereken vrije ruimte op `/var/lib/vulnix-cache` via `df`, skip met log-waarschuwing bij < 2GB vrij
- [ ] 4.2 Voeg bootstrap-detectie toe: check of `/var/lib/vulnix-cache/Data.fs` niet bestaat of kleiner is dan 1MB
- [ ] 4.3 Implementeer bootstrap-blok: `dd if=/dev/zero of=/var/lib/vulnix-cache/swap bs=1M count=1500`, `chmod 600`, `mkswap`, `swapon`
- [ ] 4.4 Voeg swapfile cleanup toe ná succesvolle vulnix run: `swapoff /var/lib/vulnix-cache/swap && rm -f /var/lib/vulnix-cache/swap`
- [ ] 4.5 Voeg `ExecStopPost` toe aan serviceConfig: `swapoff /var/lib/vulnix-cache/swap || true; rm -f /var/lib/vulnix-cache/swap`

## 5. Verifieer op fix/vulnix branch

- [ ] 5.1 Controleer dat de module bouwt: `nix build .#nixosModules.default` of equivalent
- [ ] 5.2 Verifieer dat de module correct ge-exporteerd is in `flake.nix`
