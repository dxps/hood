# Hood

A macOS shelf for switching between running apps, written in Odin and rendered
with Raylib. Odin calls macOS APIs for app discovery, icons, and activation. This is
a modified version of Karl Zylinski's Odin + Raylib + Hot Reload template.
See LICENSE for the original license notice.

## Development

With Odin on your PATH and the Xcode Command Line Tools installed, run:

```sh
./dev.sh
```

The watcher builds and launches Hood, then checks for Odin source changes
once a second. Each successful rebuild restarts the app. If compilation fails,
the last working instance stays open. Press Ctrl+C to stop the watcher and app.

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

## Settings

Right-click anywhere on the shelf, including an app icon, and choose **Settings**.
Settings opens in a separate window while the shelf stays visible.
Choose the left or right screen edge and set the icon size from 24 to 48 pixels.
Changes apply while Settings is open and are saved automatically to
`~/.config/hood/hood.toml`. Hood loads the file at startup.

```toml
edge = "left"
icon_size = 32
```
