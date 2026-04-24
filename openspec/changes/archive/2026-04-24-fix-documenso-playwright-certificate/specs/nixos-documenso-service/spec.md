## MODIFIED Requirements

### Requirement: Playwright browser availability for PDF generation
The system SHALL ensure Playwright Chromium browser is accessible despite version mismatches between Documenso expectations and nixpkgs provided version.

#### Scenario: Browser found via version compatibility symlink
- **WHEN** Documenso seal-document job requires Chromium for certificate PDF generation
- **THEN** Playwright SHALL find chromium_headless_shell at expected version path via symlink to actual nixpkgs version

#### Scenario: Browser setup at service start
- **WHEN** documenso service starts
- **THEN** ExecStartPre script SHALL create symlink from expected version (1169) to actual nixpkgs version

#### Scenario: Playwright environment configured
- **WHEN** documenso service runs
- **THEN** PLAYWRIGHT_BROWSERS_PATH SHALL point to state directory with version compatibility symlinks
- **THEN** PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD SHALL be set to "1" to prevent runtime downloads
- **THEN** PLAYWRIGHT_SKIP_VALIDATE_HOST_REQUIREMENTS SHALL be set to "1" for NixOS compatibility

#### Scenario: No runtime browser downloads
- **WHEN** Playwright checks for browsers
- **THEN** it SHALL use pre-installed nixpkgs browsers via symlinks, NOT attempt downloads

### Requirement: PKCS#12 certificate Node.js compatibility
The system SHALL generate PKCS#12 certificates using encryption algorithms compatible with Node.js PDF signing libraries.

#### Scenario: Legacy encryption format used
- **WHEN** auto-generating PKCS#12 certificate
- **THEN** OpenSSL SHALL use `-legacy` flag to generate PBES1 encryption instead of PBES2

#### Scenario: Certificate readable by Node.js libraries
- **WHEN** Documenso seal-document job reads auto-generated certificate
- **THEN** Node.js `node-forge` library SHALL successfully extract private key bags without "Failed to get private key bags" error

#### Scenario: Certificate generation command updated
- **WHEN** ExecStartPre generates certificate
- **THEN** command SHALL include `-legacy` flag in `openssl pkcs12 -export -legacy` invocation

### Requirement: S3 endpoint protocol configuration
The system SHALL configure S3 endpoint with proper protocol prefix for AWS SDK compatibility.

#### Scenario: Default endpoint includes protocol
- **WHEN** user does not specify custom S3 endpoint
- **THEN** default value SHALL be "https://s3.amazonaws.com" including https:// prefix

#### Scenario: Example values show protocol
- **WHEN** user reads S3 endpoint option documentation
- **THEN** examples SHALL include protocol prefix (e.g., "https://s3.eu-west-1.amazonaws.com")

#### Scenario: AWS SDK connection succeeds
- **WHEN** Documenso connects to S3 for document storage
- **THEN** AWS SDK SHALL successfully parse endpoint URL with protocol prefix

## ADDED Requirements

### Requirement: Playwright version compatibility
The system SHALL handle Playwright browser version mismatches between Documenso and nixpkgs automatically.

#### Scenario: Dynamic version detection
- **WHEN** ExecStartPre setup script runs
- **THEN** it SHALL detect actual nixpkgs Playwright version dynamically using `ls | grep`

#### Scenario: Symlink creation
- **WHEN** actual version differs from expected version (1169)
- **THEN** script SHALL create symlink from expected path to actual path

#### Scenario: Multiple versions handled
- **WHEN** nixpkgs updates Playwright version
- **THEN** symlink script SHALL adapt automatically without module code changes

### Requirement: Browser setup error handling
The system SHALL provide clear error messages if Playwright browser setup fails.

#### Scenario: Missing browsers directory
- **WHEN** playwright-driver.browsers is not available
- **THEN** ExecStartPre SHALL fail with error indicating missing dependency

#### Scenario: Symlink creation failure
- **WHEN** state directory permissions prevent symlink creation
- **THEN** service SHALL fail to start with clear error message about permissions
