{
  stdenvNoCC,
  lib,
  makeWrapper,
  curl,
  jq,
  yq,
  nix-prefetch-github,
}:

stdenvNoCC.mkDerivation rec {
  name = "vaultwarden-update-script";
  installPhase = ''
    mkdir -p $out/bin
    cp ${./update.sh} $out/bin/update.sh
    patchShebangs $out/bin/update.sh
    wrapProgram $out/bin/update.sh --prefix PATH : ${lib.makeBinPath buildInputs}
  '';
  dontUnpack = true;

  nativeBuildInputs = [ makeWrapper ];
  buildInputs = [
    curl
    jq
    yq
    nix-prefetch-github
  ];

  meta = {
    maintainers = [ ];
    description = "Utility to regenerate source.json for the vaultwarden package";
    mainProgram = "update.sh";
    platforms = lib.platforms.unix;
  };
}
