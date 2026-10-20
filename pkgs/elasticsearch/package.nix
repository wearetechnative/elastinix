# Elasticsearch 8, repackaged from the upstream Linux tarball.
#
# nixpkgs only ships Elasticsearch 7.17, and Zammad 7.2 requires >= 8.15.
# Modelled on nixpkgs' pkgs/servers/search/elasticsearch/7.x.nix and meant to
# run under the upstream services.elasticsearch module unchanged:
#  - es-home.patch keeps the ES_HOME that module sets (its data directory),
#    where it symlinks lib/, modules/ and plugins/;
#  - Java comes from nixpkgs (default ES_JAVA_HOME); the bundled JDK is dropped.
#    JDK >= 23 is required in practice: on 21 the launcher selects the COMPAT
#    locale provider, which instantiates ES's IsoCalendarDataProvider lazily
#    and the entitlement checks then refuse it (NotEntitledException) unless
#    log4j happened to initialise Calendar first;
#  - native code (lib/platform, x-pack-ml) is autoPatchelf'd.
{
  lib,
  stdenv,
  fetchurl,
  makeWrapper,
  autoPatchelfHook,
  jdk25_headless,
  util-linux,
  coreutils,
  gnugrep,
  zlib,
}:

let
  version = "8.19.23";
  arch =
    {
      x86_64-linux = "x86_64";
      aarch64-linux = "aarch64";
    }
    .${stdenv.hostPlatform.system} or (throw "elasticsearch: unsupported system ${stdenv.hostPlatform.system}");
  # sha512 from https://artifacts.elastic.co/downloads/elasticsearch/elasticsearch-<version>-linux-<arch>.tar.gz.sha512
  hashes = {
    x86_64 = "sha512:ccec1037814ef8051717d09adf22fde4edd93135284eb84948eb8fd82cb4e95513bb8c0780deb555e570fef549968f1d59ebe1ba81683afc6f8fab939ad03e6f";
    aarch64 = "sha512:3484ee82d493302912f3cdc8ff6ea37c5d9dfd13e77c9de01ae70866862d3b5a497fc952597a768434cbf32f512e20748e481dc6076c3a68025c17157f3f90da";
  };
in
stdenv.mkDerivation {
  pname = "elasticsearch";
  inherit version;

  src = fetchurl {
    url = "https://artifacts.elastic.co/downloads/elasticsearch/elasticsearch-${version}-linux-${arch}.tar.gz";
    hash = hashes.${arch};
  };

  patches = [ ./es-home.patch ];

  postPatch = ''
    substituteInPlace bin/elasticsearch-env --subst-var-by jdk "${jdk25_headless.home}"
  '';

  nativeBuildInputs = [
    makeWrapper
    autoPatchelfHook
  ];

  buildInputs = [
    stdenv.cc.cc.lib
    zlib
  ];

  runtimeDependencies = [ zlib ];

  dontBuild = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out
    cp -R bin config lib modules plugins $out
    chmod +x $out/bin/*

    wrapProgram $out/bin/elasticsearch \
      --prefix PATH : "${
        lib.makeBinPath [
          util-linux
          coreutils
          gnugrep
        ]
      }"

    runHook postInstall
  '';

  passthru = {
    enableUnfree = true;
  };

  meta = {
    description = "Distributed, RESTful search and analytics engine";
    homepage = "https://www.elastic.co/elasticsearch";
    sourceProvenance = with lib.sourceTypes; [
      binaryBytecode
      binaryNativeCode
    ];
    license = lib.licenses.elastic20;
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
    mainProgram = "elasticsearch";
  };
}
