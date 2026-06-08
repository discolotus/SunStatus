# SunStatus

SunStatus is a native macOS menu bar app for understanding the sun at a glance: where it is in its daily arc, how long until sunrise or sunset, and how bright the outside light is likely to feel.

The app is intended to live primarily in the menu bar. The collapsed icon should communicate the sun's position and sunset proximity. The expanded popover should show a larger solar arc, sunrise and sunset times, brightness forecasts, and eventually a 3D map-based view of the sun path and shadow direction around a location.

The current Homebrew build includes the mock daylight prototype: a menu bar status item, a SwiftUI daylight popover with a solar arc, brightness samples, a lightweight settings surface, and a 3D sun map prototype.

## Requirements

- macOS 14 or newer.
- Xcode with Swift 6 support for local builds.

## Build

Build a release archive locally:

```sh
scripts/build-release.sh 0.3.0
```

The script outputs `.build/release/SunStatus.zip` and prints the SHA-256 checksum used by the Homebrew cask.

## Install

Install SunStatus with Homebrew:

```sh
brew install --cask discolotus/sunstatus/sunstatus
```

See [ROADMAP.md](ROADMAP.md) for the implementation plan.

## Current Status

The first foundation slice is implemented as a Swift Package with:

- A macOS 14+ SwiftUI menu bar app target.
- An `NSStatusItem` menu bar entry with a compact countdown.
- A popover-style daylight panel with a mock solar arc, sunrise/sunset labels, brightness samples, and current readouts.
- A 3D panel with a MapKit satellite/elevation prototype, map-projected sun/shadow overlays, and a SceneKit companion model.
- CoreLocation-backed map centering with a clear fallback state.
- A lightweight settings/about surface.
- A testable `SunStatusCore` module with mock daylight data.

## Requirements

- macOS 14 or newer.
- Xcode with Swift 6 support.

## Run

```sh
swift run SunStatus
```

## Test

```sh
swift test
```
