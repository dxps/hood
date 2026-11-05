#!/usr/bin/env bash
set -eu
cd "$(dirname "$0")"

mkdir -p build/debug
session=$(mktemp -d "$PWD/build/debug/.live.XXXXXX")
export HOOD_UI_MANIFEST="$session/current"
# The build also creates a sibling "hood Settings" executable for the Settings process.
executable="$session/hood"
app_pid=
stop_app() {
    if [[ -n "$app_pid" ]]; then
        kill "$app_pid" 2>/dev/null || true
        wait "$app_pid" 2>/dev/null || true
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
    find source -type f \( -name '*.odin' -o -name '*.ttf' -o -name '*.m' \) ! -path 'source/ui.odin' \
        -exec shasum {} + | LC_ALL=C sort
    shasum build_debug.sh build_native.sh
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
        if ./build_debug.sh --live-ui "$executable"; then
            stop_app
            rm -f "$HOOD_UI_MANIFEST"
            "$executable" &
            app_pid=$!
            host_built=true
        fi
    elif [[ "$current_ui" != "$previous_ui" ]]; then
        previous_ui=$current_ui
        if [[ "$host_built" == true ]]; then
            generation=$((generation + 1))
            library="$session/ui-$generation.dylib"
            if odin build source -build-mode:dll -define:HOOD_UI_MODULE=true -define:RAYLIB_SHARED=true \
                -out:"$library" -strict-style -vet -debug &&
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
