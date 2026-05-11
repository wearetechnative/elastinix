## 1. Add Playwright Browser Version Compatibility

- [x] 1.1 Add Playwright environment variables to main documenso.service (PLAYWRIGHT_BROWSERS_PATH, SKIP_BROWSER_DOWNLOAD, SKIP_VALIDATE_HOST_REQUIREMENTS)
- [x] 1.2 Create ExecStartPre script to setup Playwright browser version compatibility symlinks
- [x] 1.3 Add dynamic version detection logic using ls and grep to find actual nixpkgs Playwright version
- [x] 1.4 Create symlink from expected version path (chromium_headless_shell-1169) to actual nixpkgs version
- [x] 1.5 Ensure state directory (.cache/ms-playwright) is created with proper permissions
- [x] 1.6 Add error handling for missing playwright-driver.browsers dependency

## 2. Fix PKCS#12 Certificate Generation

- [x] 2.1 Locate certificate generation ExecStartPre script in module (around signing.autoGenerate section)
- [x] 2.2 Add -legacy flag to openssl pkcs12 -export command
- [x] 2.3 Add comment explaining why -legacy flag is needed (Node.js PBES1 compatibility)
- [x] 2.4 Verify certificate generation script still includes all required parameters

## 3. Fix S3 Endpoint Configuration

- [x] 3.1 Update storage.endpoint default value from "s3.amazonaws.com" to "https://s3.amazonaws.com"
- [x] 3.2 Update storage.endpoint example value to include https:// prefix
- [x] 3.3 Verify endpoint description mentions protocol requirement

## 4. Documentation and Comments

- [x] 4.1 Add inline comments explaining Playwright version compatibility approach
- [x] 4.2 Add inline comments explaining certificate encryption compatibility
- [x] 4.3 Update docs/services/documenso.md with Playwright troubleshooting section
- [x] 4.4 Document S3 endpoint protocol requirement in docs
- [x] 4.5 Add note about issue #13 resolution in module comments

## 5. Testing and Validation

- [x] 5.1 Build configuration with nix build to verify no evaluation errors
- [ ] 5.2 Test service starts successfully and creates browser symlinks (requires deployment)
- [ ] 5.3 Verify symlink points to correct nixpkgs Playwright version (requires deployment)
- [ ] 5.4 Test certificate generation with -legacy flag produces valid PKCS#12 (requires deployment)
- [ ] 5.5 Verify OpenSSL can read generated certificate (requires deployment)
- [ ] 5.6 Test full document signing workflow (requires deployment)
- [ ] 5.7 Verify seal-document job succeeds without Playwright errors (requires deployment)
- [ ] 5.8 Verify documents transition from "Pending" to "Completed" status (requires deployment)
- [ ] 5.9 Check logs for any errors related to Playwright or certificate signing (requires deployment)
