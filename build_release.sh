#!/usr/bin/env bash
set -eu
cd "$(dirname "$0")"

contents=build/release/Hood.app/Contents
mkdir -p "$contents/MacOS" "$contents/Resources"
odin build source -out:"$contents/MacOS/Hood" -strict-style -vet -o:speed
cp Info.plist "$contents/Info.plist"
cp source/fonts/OFL.txt "$contents/Resources/WorkSans-OFL.txt"
plutil -lint "$contents/Info.plist"
codesign --force --sign - build/release/Hood.app
echo "Release built at build/release/Hood.app"
