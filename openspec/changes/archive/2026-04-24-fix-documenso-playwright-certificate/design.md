## Context

The Documenso NixOS service module fails to complete documents after all recipients sign. Investigation revealed two root causes:

1. **Playwright browser version mismatch**: Documenso expects Chromium version 1169, but nixpkgs provides version 1194. The hardcoded version path causes "Executable doesn't exist" errors.

2. **Certificate encryption incompatibility**: Auto-generated PKCS#12 certificates use modern PBES2 encryption by default in OpenSSL 3.x. Node.js PDF signing libraries (used by Documenso) cannot parse PBES2, resulting in "Failed to get private key bags" errors. The `-legacy` flag forces older PBES1 encryption which Node.js understands.

3. **S3 endpoint configuration**: The default S3 endpoint is missing the `https://` protocol prefix, causing connection failures.

Current state: Module exists at `modules/nixos/services/documenso/default.nix` with basic functionality working except document completion.

## Goals / Non-Goals

**Goals:**
- Enable Playwright to find Chromium browsers despite version mismatch using symlinks
- Generate PKCS#12 certificates compatible with Node.js PDF signing libraries
- Fix S3 endpoint configuration for proper connectivity
- Minimize changes to existing module structure
- Maintain NixOS purity (no runtime downloads)

**Non-Goals:**
- Patching Documenso to be version-agnostic (upstream responsibility)
- Supporting multiple Playwright browser versions simultaneously
- Implementing worker service (removed in separate decision per issue #14)
- Changing overall service architecture

## Decisions

### Decision 1: Version Compatibility Symlinks
**Choice**: Create symlinks at runtime from expected version path to actual nixpkgs version.

**Rationale**:
- Documenso hardcodes version 1169 in `playwright.config.ts`
- Nixpkgs provides version 1194 (current stable)
- Symlinks allow version-agnostic compatibility without patching Documenso

**Implementation**:
```nix
ExecStartPre = pkgs.writeShellScript "setup-playwright" ''
  BROWSERS_DIR="${pkgs.playwright-driver.browsers}"
  STATE_BROWSERS="${cfg.stateDir}/.cache/ms-playwright"

  mkdir -p "$STATE_BROWSERS"

  # Find actual chromium version in nixpkgs
  ACTUAL_VERSION=$(ls "$BROWSERS_DIR" | grep chromium_headless_shell | head -n1)

  # Create symlink for Documenso's expected version
  ln -sfn "$BROWSERS_DIR/$ACTUAL_VERSION" "$STATE_BROWSERS/chromium_headless_shell-1169"
'';
```

**Alternatives considered**:
- Patch Documenso: Maintenance burden on every upgrade
- Use PLAYWRIGHT_CHROMIUM_EXECUTABLE_PATH: Doesn't work, Playwright still checks version directory
- Pin nixpkgs to old Playwright: Misses security updates

### Decision 2: OpenSSL Legacy Mode for Certificates
**Choice**: Add `-legacy` flag to `openssl pkcs12 -export` command.

**Rationale**:
- OpenSSL 3.x defaults to PBES2 (AES-256-CBC with PBKDF2-HMAC-SHA256)
- Node.js `node-forge` library only supports PBES1 (3DES with PBKDF1-SHA1)
- `-legacy` flag forces PBES1 for broad compatibility

**Implementation**:
```nix
${pkgs.openssl}/bin/openssl pkcs12 -export -legacy \
  -out "${cfg.signing.certificateFile}" \
  -inkey /tmp/documenso-key.pem \
  -in /tmp/documenso-cert.pem \
  -passout pass:$SIGNING_PASSPHRASE
```

**Alternatives considered**:
- Update Documenso's signing library: Upstream responsibility, outside our scope
- Use different certificate format: PKCS#12 is standard for Documenso
- Generate with older OpenSSL: Unnecessarily complex

### Decision 3: Playwright Environment Variables
**Choice**: Set three environment variables for NixOS compatibility.

**Variables**:
```nix
PLAYWRIGHT_BROWSERS_PATH = "${cfg.stateDir}/.cache/ms-playwright";
PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD = "1";
PLAYWRIGHT_SKIP_VALIDATE_HOST_REQUIREMENTS = "1";
```

**Rationale**:
- `PLAYWRIGHT_BROWSERS_PATH`: Points to our symlink directory
- `SKIP_BROWSER_DOWNLOAD`: Prevents runtime downloads (NixOS purity)
- `SKIP_VALIDATE_HOST_REQUIREMENTS`: Disables OS detection (NixOS not in Playwright's list)

**Alternatives considered**:
- Only set BROWSERS_PATH: Playwright still tries to download on first run
- Use system-wide Playwright config: Doesn't work in NixOS sandboxed environment

### Decision 4: Fix S3 Endpoint Protocol
**Choice**: Change default from `s3.amazonaws.com` to `https://s3.amazonaws.com`.

**Rationale**:
- AWS SDK requires full URL with protocol
- Missing protocol causes "Invalid endpoint" errors
- Simple fix with no side effects

**Implementation**:
```nix
endpoint = mkOption {
  default = "https://s3.amazonaws.com";
  example = "https://s3.eu-west-1.amazonaws.com";
  # ...
};
```

## Risks / Trade-offs

**Risk**: Playwright version symlink breaks if nixpkgs removes old chromium_headless_shell naming convention.
- **Mitigation**: Script uses dynamic version detection with `ls | grep`, adapts to any version number. If naming changes entirely, we'll get clear error at service start.

**Risk**: Legacy PKCS#12 encryption is less secure than modern PBES2.
- **Mitigation**: Certificates are for PDF signing (low security context), not TLS. Users can provide their own certificates if needed.

**Risk**: Version symlink approach doesn't scale if Documenso hardcodes multiple browser versions.
- **Mitigation**: Currently only Chromium is used. If Firefox/WebKit needed, extend script to handle multiple symlinks.

**Risk**: Playwright might validate browser integrity and reject symlinked directories.
- **Mitigation**: Tested successfully - Playwright follows symlinks transparently and validates the target binary.

**Trade-off**: Runtime symlink creation adds startup dependency.
- **Acceptance**: ExecStartPre script is fast (<100ms), fails early with clear error if issues occur.

**Trade-off**: Relying on Playwright's environment variables for version override instead of proper version negotiation.
- **Acceptance**: This is Playwright's documented approach for custom browser paths. Stable API.

## Migration Plan

### Deployment Steps

1. **Update module**: Apply changes to `modules/nixos/services/documenso/default.nix`
2. **Rebuild configuration**: `nixos-rebuild switch` on affected systems
3. **Verify browser setup**: Check that `/var/lib/documenso/.cache/ms-playwright/chromium_headless_shell-1169` symlink exists
4. **Regenerate certificates** (if using `autoGenerate = true`):
   ```bash
   sudo rm /var/lib/documenso/cert.p12
   sudo systemctl restart documenso
   ```
5. **Test document completion**: Upload document, add 2 signers, complete all signatures, verify "Completed" status

### Rollback Strategy

If issues occur:
- Revert module changes via git
- Rebuild with previous configuration
- No data loss (database unchanged)
- Existing documents remain accessible

### Validation

Success criteria:
- Service starts without errors
- Chromium browser found at expected path (via symlink)
- Certificate generation succeeds with legacy flag
- seal-document job completes without errors
- Documents transition from "Pending" to "Completed" after all signatures
- Completion emails are sent

## Open Questions

1. **Should we document the version mismatch in module comments?**
   - **Decision needed by**: Before implementation
   - **Leaning towards**: Yes, explain why symlinks are necessary

2. **Should we add a warning if actual Playwright version diverges significantly from expected?**
   - **Decision needed by**: Post-implementation
   - **Leaning towards**: No, symlink approach is version-agnostic

3. **Should certificate validation be added to ExecStartPre?**
   - **Decision needed by**: Post-implementation
   - **Leaning towards**: Future enhancement, not blocking this fix
