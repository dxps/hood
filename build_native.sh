#!/usr/bin/env bash
set -eu
cd "$(dirname "$0")"
mkdir -p build/native
staging=$(mktemp -d build/native/.build.XXXXXX)
trap 'rm -rf "$staging"' EXIT
minimum_os_version=${MACOSX_DEPLOYMENT_TARGET:-$(sw_vers -productVersion)}
clang -O2 -Wall -Wextra -fobjc-arc -mmacosx-version-min="$minimum_os_version" -c source/native/shelf.m -o "$staging/shelf.o"
clang -O2 -Wall -Wextra -fobjc-arc -mmacosx-version-min="$minimum_os_version" -c source/native/settings.m -o "$staging/settings.o"
ar rcs "$staging/libhood_native.a" "$staging/shelf.o" "$staging/settings.o"
mv "$staging/libhood_native.a" build/native/libhood_native.a
