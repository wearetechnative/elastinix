# Spec Delta

## ADDED Requirements

### Requirement: Minimum pinned Zammad version

The vendored recipe SHALL pin Zammad 7.2.2 or newer. Hosts that already ran 7.2.2 must never be downgraded by a later pin.

#### Scenario: Pin is at least 7.2.2

- **WHEN** the vendored Zammad package is evaluated
- **THEN** its version is 7.2.2 or newer

#### Scenario: Package manager requirements met

- **WHEN** the pinned tag's `package.json` requires pnpm ≥ 11 and Node ≥ 24
- **THEN** the recipe builds its frontend with pnpm 11 and Node 24 from nixpkgs

## REMOVED Requirements

### Requirement: Initial Zammad version

**Reason**: It fixed the first pin at 7.1.3 for the switch from the `update-zammad` branch. That switch is done, and Zammad now moves to 7.2.2.
**Migration**: Replaced by "Minimum pinned Zammad version". Hosts follow the upgrade runbook in `docs/services/zammad.md`.
