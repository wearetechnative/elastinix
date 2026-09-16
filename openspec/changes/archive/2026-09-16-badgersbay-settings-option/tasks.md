## 1. settings as an option

- [x] 1.1 `settings` as a freeform submodule over `pkgs.formats.yaml`, with
      declared options for `networkport`, `storage_location`,
      `compliance.enabled`, `compliance.audit_months`,
      `compliance.grace_weeks` and
      `compliance.required_reports.{mandatory,one_of,per_class}`
- [x] 1.2 Defaults reproducing the heredoc the module ships today, with
      `networkport` and `storage_location` following `port` and `storagePath`
- [x] 1.3 `configFile` defaults to the rendered file and still wins when set
- [x] 1.4 Assertion: `configFile` and `settings` both explicitly set
- [x] 1.5 Assertion: `settings.compliance.asset_register` set
- [x] 1.6 Assertion: `settings.networkport` diverging from `port`, which the
      firewall and the nginx proxy follow

## 2. Assertions on the secret files

- [x] 2.1 No secret option may name a nix store path
- [x] 2.2 A path under `age.secretsDir` must match a declared `age.secrets`
      entry
- [x] 2.3 A declared secret must be readable by the service user or group
- [x] 2.4 The agenix-specific checks are skipped when the agenix module is not
      imported

## 3. Docs

- [x] 3.1 `settings` and its keys
- [x] 3.2 The configFile rule, its reasoning, and the migration off an agenix
      config secret
- [x] 3.3 The assertions and their limits
- [x] 3.4 Options table brought up to date

## 4. Verification

- [x] 4.1 Evaluate a NixOS configuration importing the module and read the
      rendered YAML back
- [x] 4.2 Evaluate the default configuration and confirm it matches the
      heredoc it replaces, key for key
- [x] 4.3 Evaluate configurations that must fail, and confirm each fails with
      its own message
