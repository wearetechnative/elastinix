---
# elastinix-pf4x
title: Remove build-breaking PORT patch from documenso module
status: todo
type: bug
priority: high
created_at: 2026-08-27T10:00:55Z
updated_at: 2026-08-27T10:00:55Z
parent: elastinix-wxy7
---

**Build blocker.** The module patches the server bundle in `postFixup` with `substituteInPlace ... --replace-fail`:

```nix
substituteInPlace $out/apps/remix/build/server/main.js \
  --replace-fail \
    "serve({ fetch: handler.fetch, port: 3000 });" \
    "serve({ fetch: handler.fetch, port: Number(process.env.PORT) || 3000 });"
```

In Documenso 2.14.0 that exact string **no longer exists**. The server now reads the port itself:

```js
parseInt(process.env.PORT || '3000', 10)
```

`--replace-fail` is designed to **fail when the pattern is missing** → the entire package build blows up. The patch is also **redundant**: verified that plain nixpkgs 2.14.0 already respects `PORT` (tested locally, bound correctly on port 3030 without the patch).

## Solution

Remove the entire `overrideAttrs`/`postFixup` override; use the package directly:

```nix
package = mkOption {
  type = types.package;
  default = pkgs.documenso;
  defaultText = literalExpression "pkgs.documenso";
  description = "Documenso package to use.";
};
```

## Acceptance criteria

- No more `substituteInPlace`/`--replace-fail` on main.js
- Package builds against nixpkgs with documenso 2.14.0
- The `port` option still works (via `PORT` in the env-file, which the module already sets)
