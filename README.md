# SunStatus

SunStatus is a native macOS menu bar app for understanding the sun at a glance: where it is in its daily arc, how long until sunrise or sunset, and how bright the outside light is likely to feel.

The app is intended to live primarily in the menu bar. The collapsed icon should communicate the sun's position and sunset proximity. The expanded popover should show a larger solar arc, sunrise and sunset times, brightness forecasts, and eventually a 3D map-based view of the sun path and shadow direction around a location.

See [ROADMAP.md](ROADMAP.md) for the implementation plan.

## Current Status

The first foundation slice is implemented as a Swift Package with:

- A macOS 14+ SwiftUI menu bar app target.
- A `MenuBarExtra` status item with a compact mock solar arc.
- A popover-style daylight panel with a mock solar arc, sunrise/sunset labels, brightness samples, and current readouts.
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
