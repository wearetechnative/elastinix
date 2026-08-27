---
# elastinix-pf4x
title: Verwijder build-brekende PORT-patch uit documenso-module
status: todo
type: bug
priority: high
created_at: 2026-08-27T10:00:55Z
updated_at: 2026-08-27T10:00:55Z
parent: elastinix-wxy7
---

**Build-blocker.** De module patcht in `postFixup` de server-bundle met `substituteInPlace ... --replace-fail`:

```nix
substituteInPlace $out/apps/remix/build/server/main.js \
  --replace-fail \
    "serve({ fetch: handler.fetch, port: 3000 });" \
    "serve({ fetch: handler.fetch, port: Number(process.env.PORT) || 3000 });"
```

In Documenso 2.14.0 bestaat die exacte string **niet meer**. De server leest de poort nu zelf:

```js
parseInt(process.env.PORT || '3000', 10)
```

`--replace-fail` is ontworpen om te **falen wanneer het patroon ontbreekt** → de volledige package-build klapt eruit. De patch is bovendien **overbodig**: geverifieerd dat kale nixpkgs-2.14.0 `PORT` al respecteert (lokaal getest, bond correct op poort 3030 zonder patch).

## Oplossing

Verwijder de hele `overrideAttrs`/`postFixup`-override; gebruik het package rechtstreeks:

```nix
package = mkOption {
  type = types.package;
  default = pkgs.documenso;
  defaultText = literalExpression "pkgs.documenso";
  description = "Documenso package to use.";
};
```

## Acceptatiecriteria

- Geen `substituteInPlace`/`--replace-fail` meer op main.js
- Package bouwt tegen nixpkgs met documenso 2.14.0
- De `port`-optie werkt nog steeds (via `PORT` in de env-file, wat de module al zet)
