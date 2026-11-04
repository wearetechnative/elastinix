{
  lib,
  stdenv,
  callPackage,
  rustPackages_1_98,
  fetchFromGitHub,
  nixosTests,
  pkg-config,
  openssl,
  libiconv,
  dbBackend ? "sqlite_system",
  libmysqlclient,
  libpq,
  sqlite,
}:

let
  source = lib.importJSON ./source.json;
  inherit (source) version;

  webvault = callPackage ./webvault.nix { inherit (source) webvault; };
in

# Vaultwarden 1.37.5 needs Rust >= 1.97.1; the default rustPlatform of
# nixos-26.05 is still 1.95.
rustPackages_1_98.rustPlatform.buildRustPackage {
  pname = "vaultwarden";
  inherit version;

  src = fetchFromGitHub (removeAttrs source [ "version" "cargoHash" "webvault" ]);

  inherit (source) cargoHash;

  # used for "Server Installed" version in admin panel
  env.VW_VERSION = version;

  nativeBuildInputs = [ pkg-config ];
  buildInputs = [
    openssl
  ]
  ++ lib.optionals stdenv.hostPlatform.isDarwin [
    libiconv
  ]
  ++ lib.optional (dbBackend == "mysql") libmysqlclient
  ++ lib.optional (dbBackend == "postgresql") libpq
  ++ lib.optional (dbBackend == "sqlite_system") sqlite;

  buildFeatures = dbBackend;

  passthru = {
    inherit webvault;
    tests = nixosTests.vaultwarden;
    updateScript = callPackage ./update.nix { };
  };

  meta = {
    description = "Unofficial Bitwarden compatible server written in Rust";
    homepage = "https://github.com/dani-garcia/vaultwarden";
    changelog = "https://github.com/dani-garcia/vaultwarden/releases/tag/${version}";
    license = lib.licenses.agpl3Only;
    mainProgram = "vaultwarden";
    platforms = lib.platforms.linux;
  };
}
