{
  stdenvNoCC,
  lib,
  makeWrapper,
  bundix,
  curl,
  gnutar,
  gzip,
  jq,
  nix-prefetch-github,
}:

stdenvNoCC.mkDerivation rec {
  name = "zammad-update-script";
  installPhase = ''
    mkdir -p $out/bin
    cp ${./update.sh} $out/bin/update.sh
    patchShebangs $out/bin/update.sh
    wrapProgram $out/bin/update.sh --prefix PATH : ${lib.makeBinPath buildInputs}
  '';
  dontUnpack = true;

  nativeBuildInputs = [ makeWrapper ];
  buildInputs = [
    bundix
    curl
    gnutar
    gzip
    jq
    nix-prefetch-github
  ];

  meta = {
    maintainers = [ ];
    description = "Utility to generate Nix expressions for Zammad's dependencies";
    mainProgram = "update.sh";
    platforms = lib.platforms.unix;
  };
}
