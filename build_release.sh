#!/usr/bin/env bash
set -eu
cd "$(dirname "$0")"
./build_native.sh

contents=build/release/Hood.app/Contents
# Target this Mac explicitly: the toolchain's inferred minimum can exceed it.
minimum_os_version=${MACOSX_DEPLOYMENT_TARGET:-$(sw_vers -productVersion)}
mkdir -p "$contents/MacOS" "$contents/Resources"
odin build source -out:"$contents/MacOS/Hood" -strict-style -vet -min-link-libs -o:speed -minimum-os-version:"$minimum_os_version"
rm -f "$contents/MacOS/Hood Settings"
cp Info.plist "$contents/Info.plist"
plutil -insert LSMinimumSystemVersion -string "$minimum_os_version" "$contents/Info.plist"
cp source/fonts/OFL.txt "$contents/Resources/WorkSans-OFL.txt"
plutil -lint "$contents/Info.plist"
codesign --force --sign - build/release/Hood.app
echo "Release built at build/release/Hood.app"
