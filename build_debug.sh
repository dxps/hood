#!/usr/bin/env bash
set -eu
cd "$(dirname "$0")"

out=build/debug
mkdir -p "$out"
staging=$(mktemp -d "$out/.build.XXXXXX")
trap 'rm -rf "$staging"' EXIT
odin build source -out:"$staging/hood" -strict-style -vet -debug
mv "$staging/hood" "$out/hood"
