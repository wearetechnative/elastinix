{
  lib,
  stdenvNoCC,
  fetchzip,
  webvault,
}:

# The prebuilt web-vault release that matches the pinned server, as published
# upstream (vault_version in docker/DockerSettings.yaml of the server tag).
stdenvNoCC.mkDerivation {
  pname = "vaultwarden-webvault";
  inherit (webvault) version;

  src = fetchzip {
    url = "https://github.com/dani-garcia/bw_web_builds/releases/download/v${webvault.version}/bw_web_v${webvault.version}.tar.gz";
    inherit (webvault) hash;
  };

  installPhase = ''
    runHook preInstall
    mkdir -p $out/share/vaultwarden
    cp -r . $out/share/vaultwarden/vault
    runHook postInstall
  '';

  meta = {
    description = "Prebuilt Bitwarden web vault for vaultwarden";
    homepage = "https://github.com/dani-garcia/bw_web_builds";
    license = lib.licenses.gpl3Plus;
    platforms = lib.platforms.all;
  };
}
