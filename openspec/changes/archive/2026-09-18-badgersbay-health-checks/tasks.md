## 1. The module

- [x] 1.1 Add `healthchecks.http.badgersbay` to `service-badgersbay.nix`, at
      `http://127.0.0.1:${cfg.port}/health` with `responseCode = 200` and
      `expectedContent = "honeybadger-server"`; verify by evaluating a
      compute2-shaped configuration and reading back the generated script's URL
      and expected code
- [x] 1.2 Add `healthchecks.localCommands.badgersbay-storage`, a
      `pkgs.writers.writePython3` script using only the standard library that
      reads `/health` and exits non-zero unless `storage.accessible` is true,
      naming `storage.location` when it fails; verify the script builds (flake8
      and the syntax check run at build time) and that the store path appears in
      `config.healthchecks.localCommands`
- [x] 1.3 Confirm the checks follow `port`: evaluate with `port = 9999` and
      verify both scripts address 9999 and not 9117

## 2. Verification

- [x] 2.1 Evaluate compute2-shaped out of tree against the real flake inputs:
      `config.healthchecks.http` and `config.healthchecks.localCommands` each
      carry a badgersbay entry, against the same evaluation at `HEAD` where both
      are `{ }`
- [x] 2.2 Instantiate `system.build.toplevel` so the module's assertions are
      forced and the check scripts are built, and confirm the built
      `badgersbay.service` unit is byte-identical to the one at `HEAD` - this
      change adds no unit and alters none
- [x] 2.3 Confirm `healthchecks.rawCommands` collects both checks with distinct
      titles, so a failure says which of the two failed
- [x] 2.4 Run the storage check script against a server that answers
      `storage.accessible: false` and against one that answers `true`, and
      confirm it exits 1 and 0 respectively - a stub HTTP server is enough,
      since the script only reads the response
- [x] 2.5 Confirm the claim the design rests on: an `expectedContent` value
      containing a double quote fails the build, so the content assertion cannot
      live in `healthchecks.http`

## 3. Docs

- [x] 3.1 `docs/services/badgersbay.md`: replace the "Monitoring / Health
      Checks" section - which suggests writing a `badgersbay-health` timer - with
      the checks the module now declares, how to run them, and why no timer is
      added
- [x] 3.2 `docs/services/badgersbay.md`: in the health endpoint section, record
      that a monitoring probe targets `/health` and never `/`, that `/` answers
      401 without credentials in every state, and that a 200 from `/health` does
      not by itself mean the storage location is there
- [x] 3.3 Verify the documented commands are the ones that exist: the endpoint
      path, the port, the check names and the way to run them
