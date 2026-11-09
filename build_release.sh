#!/usr/bin/env bash
set -eu
cd "$(dirname "$0")"
./build_native.sh release

contents=build/release/Hood.app/Contents
# Target this Mac explicitly: the toolchain's inferred minimum can exceed it.
minimum_os_version=${MACOSX_DEPLOYMENT_TARGET:-$(sw_vers -productVersion)}
mkdir -p "$contents/MacOS" "$contents/Resources"
odin build source -out:"$contents/MacOS/Hood" -strict-style -vet -min-link-libs -o:speed -minimum-os-version:"$minimum_os_version"
rm -f "$contents/MacOS/Hood Settings"
settings_contents="$contents/Helpers/Hood Settings.app/Contents"
mkdir -p "$settings_contents/MacOS" "$settings_contents/Resources"
cp "$contents/MacOS/Hood" "$settings_contents/MacOS/Hood Settings"
cp HoodSettings-Info.plist "$settings_contents/Info.plist"
plutil -insert LSMinimumSystemVersion -string "$minimum_os_version" "$settings_contents/Info.plist"
cp source/assets/Hood.icns "$settings_contents/Resources/Hood.icns"
plutil -lint "$settings_contents/Info.plist"
codesign --force --sign - "$contents/Helpers/Hood Settings.app"
cp Info.plist "$contents/Info.plist"
plutil -insert LSMinimumSystemVersion -string "$minimum_os_version" "$contents/Info.plist"
cp source/assets/Hood.icns "$contents/Resources/Hood.icns"
cp source/fonts/OFL.txt "$contents/Resources/WorkSans-OFL.txt"
plutil -lint "$contents/Info.plist"
codesign --force --sign - build/release/Hood.app
echo "Release built at build/release/Hood.app"
