#!/usr/bin/env bash
set -eu
cd "$(dirname "$0")"

minimum_os_version=${MACOSX_DEPLOYMENT_TARGET:-$(sw_vers -productVersion)}
mkdir -p build/debug
session=$(mktemp -d "$PWD/build/debug/.live.XXXXXX")
export HOOD_UI_MANIFEST="$session/current"
# Keep the app identity stable across watcher sessions. Only reload artifacts
# and the manifest live in the temporary session directory.
app_bundle="$PWD/build/debug/Hood.app"
app_pid=
stop_app() {
    if [[ -n "$app_pid" ]]; then
        kill "$app_pid" 2>/dev/null || true
        # LaunchServices owns the process, so it is not a child we can wait for.
        for ((attempt=0; attempt<50; attempt++)); do
            if ! kill -0 "$app_pid" 2>/dev/null; then break; fi
            sleep 0.1
        done
        app_pid=
    fi
}
cleanup() {
    stop_app
    rm -rf "$session"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

host_snapshot() {
    find source -type f \( -name '*.odin' -o -name '*.ttf' -o -name '*.m' -o -name '*.h' -o -name '*.icns' \) ! -path 'source/ui.odin' \
        -exec shasum {} + | LC_ALL=C sort
    shasum build_debug.sh build_native.sh build_dev.sh Info.plist
}

previous_host=
previous_ui=
host_built=false
generation=0
while true; do
    current_host=$(host_snapshot)
    current_ui=$(shasum source/ui.odin)
    if [[ "$current_host" != "$previous_host" ]]; then
        previous_host=$current_host
        previous_ui=$current_ui
        host_built=false
        if ./build_dev.sh; then
            stop_app
            rm -f "$HOOD_UI_MANIFEST"
            app_pid=$(build/debug/hood-launch "$app_bundle" "$HOOD_UI_MANIFEST")
            host_built=true
        fi
    elif [[ "$current_ui" != "$previous_ui" ]]; then
        previous_ui=$current_ui
        if [[ "$host_built" == true ]]; then
            generation=$((generation + 1))
            library="$session/ui-$generation.dylib"
            if odin build source -build-mode:dll -define:HOOD_UI_MODULE=true -define:RAYLIB_SHARED=true \
				-out:"$library" -strict-style -vet -min-link-libs -debug -minimum-os-version:"$minimum_os_version" &&
                [[ "$(host_snapshot)" == "$current_host" ]]; then
                printf '%s\n' "$library" > "$session/next"
                mv "$session/next" "$HOOD_UI_MANIFEST"
            fi
        else
            # A UI edit can fix a failed host build. Retry the whole build.
            previous_host=
        fi
    fi
    sleep 1
done
