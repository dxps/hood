#!/usr/bin/env bash
set -eu
cd "$(dirname "$0")"

minimum_os_version=${MACOSX_DEPLOYMENT_TARGET:-$(sw_vers -productVersion)}
mkdir -p build/debug
# The watcher and a manual build may run together; serialize bundle publication.
lock=build/debug/.app-build-lock
attempt=0
until mkdir "$lock" 2>/dev/null; do
    attempt=$((attempt + 1))
    if [[ $attempt -ge 300 ]]; then
        printf 'Another development build holds %s; try again when it finishes.\n' "$lock" >&2
        exit 1
    fi
    sleep 0.1
done
staging=
trap '[[ -z "$staging" ]] || rm -rf "$staging"; rmdir "$lock"' EXIT
staging=$(mktemp -d build/debug/.app.XXXXXX)
clang -mmacosx-version-min="$minimum_os_version" -O2 -Wall -Wextra -fobjc-arc -framework AppKit source/native/launch.m -o "$staging/hood-launch"
contents="$staging/Hood.app/Contents"
mkdir -p "$contents/MacOS" "$contents/Resources"
./build_debug.sh --live-ui "$contents/MacOS/Hood"
cp Info.plist "$contents/Info.plist"
plutil -insert LSMinimumSystemVersion -string "$minimum_os_version" "$contents/Info.plist"
# Separate development permissions and app registration from the release app.
plutil -replace CFBundleIdentifier -string dev.dxps.hood.debug "$contents/Info.plist"
cp source/assets/Hood.icns "$contents/Resources/Hood.icns"
cp source/fonts/OFL.txt "$contents/Resources/WorkSans-OFL.txt"
plutil -lint "$contents/Info.plist"
codesign --force --sign - "$staging/Hood.app"

# Publish only after the complete bundle builds and signs successfully.
if [[ -e build/debug/Hood.app ]]; then
    mv build/debug/Hood.app "$staging/previous.app"
fi
if ! mv "$staging/Hood.app" build/debug/Hood.app; then
    if [[ -e "$staging/previous.app" ]]; then
        mv "$staging/previous.app" build/debug/Hood.app
    fi
    exit 1
fi
mv "$staging/hood-launch" build/debug/hood-launch
printf 'Development app built at build/debug/Hood.app\n'
