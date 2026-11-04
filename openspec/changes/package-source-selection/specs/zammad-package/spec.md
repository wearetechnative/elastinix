# Spec Delta

## MODIFIED Requirements

### Requirement: Default package of the zammad service

The default of `elastinix.services.zammad.package` (type `lib.types.package`) SHALL be the package selected by `elastinix.services.zammad.source`, whose default `"pinned"` yields the vendored Zammad build. Consumers SHALL still be able to override the option with any other package.

#### Scenario: Default uses vendored build

- **WHEN** a host enables `elastinix.services.zammad` without setting `package` or `source`
- **THEN** `services.zammad.package` is the vendored Zammad build at the version from `source.json`

#### Scenario: Default follows source

- **WHEN** a host sets `elastinix.services.zammad.source = "nixpkgs"` without setting `package`
- **THEN** `services.zammad.package` is `pkgs.zammad` from the main nixpkgs input

#### Scenario: Consumer override is respected

- **WHEN** a host sets `elastinix.services.zammad.package = pkgs.zammad`
- **THEN** that package is used instead of the vendored build
