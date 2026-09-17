## 1. The trigger list

- [x] 1.1 `runtimeFiles`: every file the server reads at startup - `configFile`
      plus the existing `secretFiles` - kept separate from `secretFiles`, which
      the assertions iterate and which `configFile` does not belong to
- [x] 1.2 `fileTriggers`: a file's path, plus the `age.secrets` entry's `file`
      when `declaredSecret` finds one, reusing the lookup the assertions use
- [x] 1.3 Comment recording why the path alone cannot be the trigger for an
      agenix secret, and why the ciphertext can be

## 2. The unit

- [x] 2.1 `restartTriggers` on `systemd.services.badgersbay`, built from
      `runtimeFiles`
- [x] 2.2 No trigger contributed by `assetRegisterFile` when it is not set

## 3. Verification

- [x] 3.1 Evaluate compute2-shaped: all four files agenix secrets at
      `/run/agenix` paths; assert every path and every `.age` source is present
- [x] 3.2 Evaluate that editing one secret's ciphertext changes the list, and
      that leaving everything alone does not
- [x] 3.3 Evaluate default-shaped: generated `configFile`, no register; assert
      the generated config is covered and no register trigger appears
- [x] 3.4 Evaluate without the agenix module imported, confirming the module
      still evaluates and falls back to paths alone
- [x] 3.5 `nix build` the module's host closure to confirm the unit builds

## 4. Docs

- [x] 4.1 `docs/services/badgersbay.md`: that a changed secret restarts the
      service, that re-encryption alone does too, and that a hand-placed file
      outside the store and outside agenix is not covered
