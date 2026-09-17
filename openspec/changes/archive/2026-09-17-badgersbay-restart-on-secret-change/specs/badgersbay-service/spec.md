## ADDED Requirements

### Requirement: Carry a changed input into the running process

The server reads its configuration, its API tokens, its dashboard password and
its asset register once, at startup. The module SHALL declare
`restartTriggers` on the unit such that a deploy which changes any of those
files restarts the service, so that what is on disk is what the process is
serving.

For a file delivered by agenix the path is stable and the decrypted content is
not readable at evaluation, so the trigger SHALL also include the `age.secrets`
entry that produces the path - the encrypted source, whose store path follows
the ciphertext.

#### Scenario: A rotated token
- **WHEN** an agenix secret behind `tokenFile` is re-encrypted with a new token
  and deployed
- **THEN** badgersbay is restarted and accepts the new token, rather than
  continuing to accept the old one and reject the new one - two behaviours that
  both look like the system working

#### Scenario: A configuration delivered as a secret
- **WHEN** `configFile` names an agenix path, as compute2 sets it, and the
  secret's content changes
- **THEN** badgersbay is restarted, because the path the unit interpolates is
  the same string before and after the rewrite and cannot be the trigger by
  itself

#### Scenario: A configuration rendered from settings
- **WHEN** `configFile` is the file rendered from `settings` and a value changes
- **THEN** badgersbay is restarted, as the generated file is a store path that
  changes with its content

#### Scenario: A replaced asset register
- **WHEN** the register is reissued because people joined, left or swapped
  machines
- **THEN** badgersbay is restarted and the compliance figure is measured against
  the new register

#### Scenario: Restarted after the secret is written
- **WHEN** the restart is triggered by an agenix secret
- **THEN** the new content is in place before the service starts:
  `switch-to-configuration` stops the units it must restart, runs the activation
  scripts that decrypt the secrets, and only then starts them

#### Scenario: A register the server rejects, on a restart
- **WHEN** a reissued register contains a duplicate active serial, an unknown
  platform class or an unparseable date
- **THEN** the restart fails and the service stays down, which is the same
  refusal it makes at first start and is visible in the unit state - rather than
  a running service quietly measuring against the previous register

#### Scenario: Re-encrypted without an edit
- **WHEN** a secret is re-encrypted without its plaintext changing, for example
  to add a host key
- **THEN** badgersbay is restarted anyway, because age ciphertext differs on
  every encryption. A restart nobody needed costs seconds; a restart that did
  not happen is what this requirement exists for

#### Scenario: Nothing changed
- **WHEN** a deploy changes none of the four files
- **THEN** the unit is unchanged and the service is not restarted

#### Scenario: What the triggers do not cover
- **WHEN** a secret option names a file that is neither in the nix store nor
  produced by an `age.secrets` entry - a file placed on the host by hand
- **THEN** only its path can be a trigger, and a change to its content does not
  restart the service. Nothing readable at evaluation tracks that file, and the
  module does not claim otherwise
