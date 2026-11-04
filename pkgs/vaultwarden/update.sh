#!/usr/bin/env bash

set -euo pipefail

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ] || [[ "$1" == -* ]]; then
  echo "Regenerates source.json for the vaultwarden package at an upstream tag."
  echo "Usage: update.sh <tag> [vaultwarden package directory]"
  echo "Example: update.sh 1.37.5 ./pkgs/vaultwarden"
  exit 1
fi

VERSION="$1"
TARGET_DIR="$(realpath "${2:-$(dirname "$(realpath "$0")")}")"
if [[ "$TARGET_DIR" == /nix/store/* ]]; then
  echo "Target directory $TARGET_DIR is in the Nix store; pass the vaultwarden package directory, e.g. ./pkgs/vaultwarden"
  exit 1
fi
WORK_DIR=$(mktemp -d)

# Delete the working directory on exit.
function cleanup {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

echo ":: Prefetching vaultwarden $VERSION"
nix-prefetch-github dani-garcia vaultwarden --rev "$VERSION" --json > "$WORK_DIR/server.json"

echo ":: Reading the matching web-vault version"
WEBVAULT_VERSION=$(curl -fsL "https://raw.githubusercontent.com/dani-garcia/vaultwarden/$VERSION/docker/DockerSettings.yaml" \
  | yq -r '.vault_version' | sed 's/^v//')

echo ":: Prefetching web-vault $WEBVAULT_VERSION"
WEBVAULT_HASH=$(nix store prefetch-file --unpack --json \
  "https://github.com/dani-garcia/bw_web_builds/releases/download/v$WEBVAULT_VERSION/bw_web_v$WEBVAULT_VERSION.tar.gz" \
  | jq -r '.hash')

jq --arg version "$VERSION" --arg wv "$WEBVAULT_VERSION" --arg wvh "$WEBVAULT_HASH" \
  '{owner, repo, rev, hash} + {cargoHash: "", version: $version, webvault: {version: $wv, hash: $wvh}}' \
  "$WORK_DIR/server.json" > "$WORK_DIR/source.json"

# Only touch the target directory once everything has been generated.
mv "$WORK_DIR/source.json" "$TARGET_DIR/source.json"

echo
echo ":: Done: source.json now pins vaultwarden $VERSION with web-vault $WEBVAULT_VERSION."
echo ":: Next: run 'nix build .#vaultwarden' and paste the 'got:' hash into"
echo "::       cargoHash in source.json."
