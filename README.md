# SunStatus

SunStatus is a native macOS menu bar app for understanding the sun at a glance: where it is in its daily arc, how long until sunrise or sunset, and how bright the outside light is likely to feel.

The app is intended to live primarily in the menu bar. The collapsed icon should communicate the sun's position and sunset proximity. The expanded popover should show a larger solar arc, sunrise and sunset times, brightness forecasts, and eventually a 3D map-based view of the sun path and shadow direction around a location.

The current Homebrew build includes the mock daylight prototype: a menu bar status item, a SwiftUI daylight popover with a solar arc, brightness samples, and a lightweight settings surface.

## Requirements

- macOS 14 or newer.
- Xcode with Swift 6 support for local builds.

## Build

Build a release archive locally:

```sh
scripts/build-release.sh 0.2.2
```

The script outputs `.build/release/SunStatus.zip` and prints the SHA-256 checksum used by the Homebrew cask.

## Install

Install SunStatus with Homebrew:

```sh
brew install --cask discolotus/sunstatus/sunstatus
```

See [ROADMAP.md](ROADMAP.md) for the implementation plan.
