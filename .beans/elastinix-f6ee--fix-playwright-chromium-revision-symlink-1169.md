---
# elastinix-f6ee
title: Fix Playwright chromium-revision symlink (1169 -> bundled)
status: todo
type: bug
priority: high
created_at: 2026-08-27T10:00:57Z
updated_at: 2026-08-27T10:00:57Z
parent: elastinix-wxy7
---

**Runtime blocker.** The `ExecStartPre` "playwright-setup" creates a symlink with the name Documenso expects:

```bash
ln -sfn "$NIXPKGS_BROWSERS/$ACTUAL_VERSION" "$STATE_BROWSERS/chromium_headless_shell-1169"
```

The *source* (`ACTUAL_VERSION`) is dynamic (fine), but the *target name* `chromium_headless_shell-1169` is hardcoded. Documenso 2.14.0 bundles **Playwright 1.56.1**, which expects chromium-headless-shell **revision 1194** (from `node_modules/playwright-core/browsers.json`). So Documenso looks for `chromium_headless_shell-1194` in `PLAYWRIGHT_BROWSERS_PATH`, does not find the `-1169` symlink → headless chromium not found → PDF/rendering features fail at runtime.

## Solution (recommended: version-independent)

Derive the expected revision from the package itself instead of a hardcoded number, so it survives future Playwright bumps:

```bash
EXPECTED=$(${pkgs.jq}/bin/jq -r \
  '.browsers[] | select(.name=="chromium-headless-shell") | .revision' \
  ${cfg.package}/node_modules/playwright-core/browsers.json)
ln -sfn "$NIXPKGS_BROWSERS/$ACTUAL_VERSION" "$STATE_BROWSERS/chromium_headless_shell-$EXPECTED"
```

Minimal variant (only for 2.14.0): `-1169` → `-1194`.

## Point of attention

Make sure the nixpkgs pin provides a `playwright-driver.browsers` that contains a chromium-headless-shell compatible with Playwright 1.56.1 (revision near 1194). Verify this at the nixpkgs bump (story 4).

## Acceptance criteria

- Symlink target name matches the revision the bundled Playwright expects
- Documenso finds chromium when generating/rendering a signed PDF
- Preferably derived dynamically, not hardcoded again
