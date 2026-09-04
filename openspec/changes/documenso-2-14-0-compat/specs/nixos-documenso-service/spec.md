## MODIFIED Requirements

### Requirement: Playwright browser availability for PDF generation
The system SHALL ensure the Playwright chromium-headless-shell browser is accessible at the revision the packaged Documenso Playwright expects, provided as a build-time artifact from the nixpkgs-supplied `playwright-driver.browsers`.

#### Scenario: Browser found via revision-named store entry
- **WHEN** a Documenso seal-document job requires chromium-headless-shell for certificate PDF generation
- **THEN** Playwright SHALL find `chromium_headless_shell-<expected-revision>` under `PLAYWRIGHT_BROWSERS_PATH`, where `<expected-revision>` matches the revision declared by the packaged Playwright

#### Scenario: Browsers provided as a build-time derivation
- **WHEN** the documenso module is built
- **THEN** the browsers tree SHALL be produced by a build-time derivation that mirrors `pkgs.playwright-driver.browsers` and adds a `chromium_headless_shell-<expected-revision>` entry
- **THEN** no runtime `ExecStartPre` step SHALL create browser symlinks

#### Scenario: Playwright environment configured
- **WHEN** the documenso service runs
- **THEN** `PLAYWRIGHT_BROWSERS_PATH` SHALL point directly at the read-only store path of the build-time browsers derivation
- **THEN** `PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD` SHALL be set to "1" to prevent runtime downloads
- **THEN** `PLAYWRIGHT_SKIP_VALIDATE_HOST_REQUIREMENTS` SHALL be set to "1" for NixOS compatibility

#### Scenario: No runtime browser downloads and no state-directory browser cache
- **WHEN** Playwright checks for browsers
- **THEN** it SHALL use the store-provided browsers derivation, NOT attempt downloads
- **THEN** the module SHALL NOT create or depend on a browser cache under the service state directory

### Requirement: Playwright version compatibility
The system SHALL handle Playwright browser revision mismatches between the packaged Documenso and nixpkgs automatically, deriving the expected revision from the package rather than hardcoding it.

#### Scenario: Expected revision derived from the package
- **WHEN** the browsers derivation is built
- **THEN** the expected chromium-headless-shell revision SHALL be read at build time from the packaged `playwright-core/browsers.json` (the entry named `chromium-headless-shell`)
- **THEN** the module SHALL NOT contain a hardcoded chromium revision number

#### Scenario: Revision mapping created
- **WHEN** the revision provided by `playwright-driver.browsers` differs from the expected revision
- **THEN** the derivation SHALL expose the provided chromium-headless-shell under the expected revision name

#### Scenario: Future bumps handled automatically
- **WHEN** nixpkgs updates its Playwright browser revision, or Documenso updates its vendored Playwright
- **THEN** the derived expected revision and the mapping SHALL adapt without module code changes

### Requirement: Browser setup error handling
The system SHALL fail loudly at build time if the Playwright chromium-headless-shell browser cannot be provided.

#### Scenario: Missing chromium-headless-shell in the driver
- **WHEN** `playwright-driver.browsers` contains no `chromium_headless_shell-*` entry
- **THEN** the browsers derivation build SHALL fail with a clear error indicating the missing browser
- **THEN** the failure SHALL occur during `nixos-rebuild`, before deployment, not at service start

## ADDED Requirements

### Requirement: Documenso package uses the unmodified nixpkgs build
The system SHALL use the nixpkgs-provided `documenso` package without a `postFixup` source patch, relying on Documenso's native handling of the configured port.

#### Scenario: No source-string patch applied to the server bundle
- **WHEN** the documenso package option resolves to its default
- **THEN** it SHALL be `pkgs.documenso` with no `substituteInPlace`/`--replace-fail` override of the server bundle

#### Scenario: Package builds against Documenso 2.14.0
- **WHEN** the module is built against a nixpkgs revision providing `documenso-2.14.0`
- **THEN** the package SHALL build without a `--replace-fail` pattern-not-found error

#### Scenario: Configured port is honoured
- **WHEN** `services.documenso.port` is set and the service starts
- **THEN** Documenso SHALL listen on that port, via the `PORT` value the module writes into the generated environment file

### Requirement: License file write failure is non-fatal
The system SHALL continue to operate when Documenso cannot persist its license cache file to the read-only store, and this behaviour SHALL be documented.

#### Scenario: EROFS on license write does not stop the service
- **WHEN** Documenso attempts to write `.documenso-license.json` and the write fails with EROFS because the working directory is the read-only store
- **THEN** the service SHALL continue starting and running normally, with the license check resolving to the community edition

#### Scenario: Behaviour is documented
- **WHEN** an operator reads `docs/services/documenso.md`
- **THEN** it SHALL state that the EROFS license-write log line is expected and harmless
