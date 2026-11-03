#!/usr/bin/env bash
set -eu
cd "$(dirname "$0")"

out=build/debug
mkdir -p "$out"
staging=$(mktemp -d "$out/.build.XXXXXX")
trap 'rm -rf "$staging"' EXIT
flags=()
if [[ ${1:-} == "--live-ui" ]]; then
    flags=(-define:HOOD_LIVE_UI=true -define:RAYLIB_SHARED=true)
fi
odin build source ${flags[@]+"${flags[@]}"} -out:"$staging/hood" -strict-style -vet -debug
mv "$staging/hood" "$out/hood"
