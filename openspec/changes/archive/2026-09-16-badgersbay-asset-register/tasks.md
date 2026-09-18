## 1. The option

- [x] 1.1 `assetRegisterFile` as `types.nullOr types.path`, defaulting to null
- [x] 1.2 Description naming the CSV's origin and the agenix pattern, matching
      how `tokenFile` and `dashboardPasswordFile` are documented
- [x] 1.3 Example pointing at `config.age.secrets.badgersbay-assets.path`

## 2. Starting the service

- [x] 2.1 Pass `--asset-register` when the option is set
- [x] 2.2 Omit the argument entirely when it is not, so a host without a
      register runs as it does today

## 3. Docs

- [x] 3.1 `docs/services/badgersbay.md`: the option, where the CSV comes from,
      and that a register the server cannot trust stops it from starting
