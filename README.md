# Hood

A macOS shelf for switching between running apps, written in Odin and rendered
with Raylib. Odin calls macOS APIs for app discovery, icons, and activation. This is
based on Karl Zylinski's Odin + Raylib + Hot Reload [template](https://github.com/karl-zylinski/odin-raylib-hot-reload-game-template).

## Development

With Odin on your PATH and the Xcode Command Line Tools installed, run:

```sh
./dev.sh
```

The watcher checks for changes once a second. Edit `source/ui.odin` to reload
shelf drawing and the Settings UI in their existing windows. Edits to the host,
configuration code, native integration, or font rebuild and restart Hood.
A failed build leaves the last working version running. Press Ctrl+C to stop
the watcher and app.

Live reload uses the shared macOS Raylib library supplied by the Odin toolchain.
The standalone debug and release builds use the statically linked Raylib library.

Run `./build_debug.sh` to compile a debug executable without starting the watcher.

Click an app icon to switch to it. Scroll if the icons exceed the shelf height.
Press Escape while the shelf has focus to close it.

## Release

```sh
./build_release.sh
open build/release/Hood.app
```

You can also double-click Hood.app in Finder. The build targets the architecture
of the build machine and applies an ad hoc signature for local use.
The minimum macOS version defaults to the build machine's installed version and
is set explicitly in both the executable and app bundle. To target another
version, run `MACOSX_DEPLOYMENT_TARGET=27.0 ./build_release.sh` (replace `27.0`
with your target). Odin and its linked libraries must also support that version.

## Settings

Right-click anywhere on the shelf, including an app icon, and choose **Settings**.
Settings opens in a separate window while the shelf stays visible.
Choose the left, right, bottom, or top screen edge and set the icon size from 24 to 48 pixels.
Changes apply while Settings is open and are saved automatically to
`~/.config/hood/hood.toml`. Hood loads the file at startup.

Right-click an app icon and choose **Keep in Dock** to keep it available after
the app quits. The checked item can be selected again to remove it. Clicking a
kept app that is not running launches it. Dragged icon order is restored when
Hood restarts; stopped apps in that order remain hidden unless they are kept.

```toml
edge = "left"
icon_size = 32
```
