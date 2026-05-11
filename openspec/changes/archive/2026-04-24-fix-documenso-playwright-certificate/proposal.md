## Why

Documenso document completion fails when all signers have signed - documents remain in "Pending" status instead of transitioning to "Completed". Root cause analysis revealed two blocking issues: (1) Playwright browser version mismatch between Documenso's expected version (1169) and nixpkgs provided version (1194), causing PDF certificate generation to fail, and (2) auto-generated PKCS#12 certificates using modern PBES2 encryption which Node.js PDF signing libraries cannot parse, resulting in "Failed to get private key bags" errors.

## What Changes

- Add Playwright browser compatibility layer with version-agnostic symlinks pointing nixpkgs browsers to Documenso's expected version paths
- Configure PLAYWRIGHT_BROWSERS_PATH, PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD, and PLAYWRIGHT_SKIP_VALIDATE_HOST_REQUIREMENTS environment variables for NixOS compatibility
- Add systemd ExecStartPre script to create browser version compatibility symlinks at service startup
- Update certificate generation to use OpenSSL `-legacy` flag for PKCS#12 export, ensuring Node.js library compatibility
- Fix S3 endpoint configuration to include `https://` protocol prefix (discovered during testing)

## Capabilities

### New Capabilities

None - this change fixes existing functionality rather than adding new capabilities.

### Modified Capabilities

- `nixos-documenso-service`: Update document completion workflow to handle Playwright browser version mismatches and certificate format requirements on NixOS

## Impact

**Code**:
- `modules/nixos/services/documenso/default.nix`: Add Playwright environment configuration, browser setup script, and certificate generation flag

**Dependencies**:
- Adds runtime dependency on `playwright-driver.browsers` from nixpkgs for pre-packaged Playwright browsers

**Resolves**:
- Closes issue #13 (Playwright and certificate blocking document completion)
- Addresses concerns from issue #14 (worker service architecture - separate fix removed worker service entirely)

**Testing Impact**:
- Requires full document signing flow test (upload document, add 2 signers, complete all signatures, verify transition to "Completed" status)
