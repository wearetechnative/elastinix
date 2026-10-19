#!/usr/bin/env bash

set -euo pipefail

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ] || [[ "$1" == -* ]]; then
  echo "Regenerates packaging data for the zammad package at an upstream tag."
  echo "Usage: update.sh <tag> [zammad package directory]"
  echo "Example: update.sh 7.1.3 ./pkgs/zammad"
  exit 1
fi

VERSION="$1"
TARGET_DIR="$(realpath "${2:-$(dirname "$(realpath "$0")")}")"
if [[ "$TARGET_DIR" == /nix/store/* ]]; then
  echo "Target directory $TARGET_DIR is in the Nix store; pass the zammad package directory, e.g. ./pkgs/zammad"
  exit 1
fi
WORK_DIR=$(mktemp -d)
SOURCE_DIR=$WORK_DIR/zammad-$VERSION

# Check that working directory was created.
if [[ ! "$WORK_DIR" || ! -d "$WORK_DIR" ]]; then
    echo "Could not create temporary directory."
    exit 1
fi

# Delete the working directory on exit.
function cleanup {
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

pushd "$WORK_DIR"

echo ":: Creating source.json"
nix-prefetch-github zammad zammad --rev "$VERSION" --json --fetch-submodules \
  | jq --arg version "$VERSION" 'del(.leaveDotGit) | del(.deepClone) | . + {version: $version}' \
  > source.json

echo ":: Fetching source"
curl -fL "https://github.com/zammad/zammad/archive/$VERSION.tar.gz" --output source.tar.gz
tar zxf source.tar.gz

if [[ ! "$SOURCE_DIR" || ! -d "$SOURCE_DIR" ]]; then
    echo "Source directory does not exists."
    exit 1
fi

pushd "$SOURCE_DIR"

echo ":: Creating gemset.nix"
bundix --lockfile=./Gemfile.lock --gemfile=./Gemfile --gemset="$WORK_DIR/gemset.nix"

popd
popd

# Only touch the target directory once everything has been generated.
mv "$WORK_DIR/source.json" "$TARGET_DIR/source.json"
mv "$WORK_DIR/gemset.nix" "$TARGET_DIR/gemset.nix"

echo
echo ":: Done: source.json and gemset.nix now pin zammad $VERSION."
echo ":: Next: set pnpmDeps.hash in package.nix to lib.fakeHash, run"
echo "::       'nix build .#zammad', and paste the 'got:' hash back in."
