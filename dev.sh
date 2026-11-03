#!/usr/bin/env bash
set -eu
cd "$(dirname "$0")"

app_pid=
stop_app() {
    if [[ -n "$app_pid" ]]; then
        kill "$app_pid" 2>/dev/null || true
        wait "$app_pid" 2>/dev/null || true
        app_pid=
    fi
}
trap stop_app EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

snapshot() {
    find source -type f \( -name '*.odin' -o -name '*.ttf' \) -exec shasum {} + | LC_ALL=C sort
}

previous=
while true; do
    current=$(snapshot)
    if [[ "$current" != "$previous" ]]; then
        previous=$current
        if ./build_debug.sh; then
            stop_app
            ./build/debug/hood &
            app_pid=$!
        fi
    fi
    sleep 1
done
