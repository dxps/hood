#!/usr/bin/env bash
set -eu
cd "$(dirname "$0")"
minimum_os_version=${MACOSX_DEPLOYMENT_TARGET:-$(sw_vers -productVersion)}
./build_native.sh debug

output=${2:-build/debug/hood}
out=$(dirname "$output")
mkdir -p "$out"
staging=$(mktemp -d "$out/.build.XXXXXX")
trap 'rm -rf "$staging"' EXIT
flags=()
if [[ ${1:-} == "--live-ui" ]]; then
    flags=(-define:HOOD_LIVE_UI=true -define:RAYLIB_SHARED=true)
fi
odin build source ${flags[@]+"${flags[@]}"} -out:"$staging/hood" -strict-style -vet -min-link-libs -debug -minimum-os-version:"$minimum_os_version"
mv "$staging/hood" "$output"
# Remove the obsolete helper produced by older builds. Settings now renames the
# shared process through NSProcessInfo instead of shipping a second executable.
rm -f "$output Settings"
