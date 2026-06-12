# SunStatus

[![Buy Me a Coffee](https://img.shields.io/badge/Buy%20Me%20a%20Coffee-support-FDD231?style=for-the-badge&logo=buymeacoffee&logoColor=000)](https://buymeacoffee.com/tannermleoy)

SunStatus is a native macOS menu bar app for understanding the sun at a glance: where it is in its daily arc, how long until the next daylight transition, and how bright the outside light is likely to feel.

<p align="center">
  <img src="Docs/Images/sunstatus-widget.png" alt="SunStatus desktop widget showing the sun arc and daylight stats" width="360">
</p>

<p align="center">
  <img src="Docs/Images/sunstatus-expanded-map.png" alt="SunStatus expanded 3D map showing the sun arc, projected ground path, sun direction, and shadow direction" width="720">
</p>

## Key Features

- Native macOS menu bar app with a compact countdown status item, popover, pinned widget, and expanded map window.
- macOS desktop WidgetKit widgets, built as a native Xcode widget extension target, with small, medium, and large SunStatus layouts for the sun arc, daylight progress, brightness, next transition, and solar elevation.
- Real solar-position calculations for the selected coordinate, including sunrise, solar noon, sunset, elevation, azimuth, and daylight progress.
- Apple Maps 3D satellite terrain view with realistic elevation, pitch, rotation, zoom, compass, and map controls.
- 3D sun path overlay with Mercator-aware projection correction so the arc stays aligned as the map pans.
- Dashed 2D ground projections for the sun path and current sun direction, plus current shadow bearing and terrain-projected location rings.
- Current-location centering for the widget and expanded map, with status text and solar geometry refreshed for the resolved coordinate.
- Slowly rotating compact 3D widget camera that pauses for 30 seconds when the user interacts with the map.
- Time scrubber for previewing the day path, elevation, azimuth, shadow direction, and brightness at different moments.
- Weather-enriched brightness using Open-Meteo cloud cover, UV index, visibility, and interpolated hourly cloud-cover samples.
- Release and local-run scripts that generate the app bundle icon from `Assets/AppIcon.png`.

## Requirements

- macOS 14 or newer.
- Xcode with Swift 6 support.
- XcodeGen 2.45 or newer if you want to regenerate `SunStatus.xcodeproj` from `project.yml`. The checked-in project can be opened directly in Xcode.

## Install

Install SunStatus with Homebrew once the tap has been published:

```sh
brew tap discolotus/sunstatus
brew install --cask discolotus/sunstatus/sunstatus
```

Or download `SunStatus.dmg` from the matching GitHub release, open it, and drag `SunStatus.app` to Applications.

SunStatus is currently ad-hoc signed rather than Developer ID signed and notarized. On first launch, macOS may require Control-click > Open or approval in System Settings > Privacy & Security. SunStatus is a menu bar app, so it appears in Applications and the menu bar, not the Dock.

After installing and launching SunStatus, add the desktop widget from the macOS widget gallery. The widget requests location access through WidgetKit and falls back to San Francisco daylight data if location is unavailable.

## Support

SunStatus is free while the release candidate matures. If the app is useful to you, you can support development through [GitHub Sponsors](https://github.com/sponsors/discolotus) or [Buy Me a Coffee](https://buymeacoffee.com/tannermleoy). The in-app Settings window includes both support links.

To finish setup:

- Enable GitHub Sponsors for the `discolotus` account or organization.
- Create a Buy Me a Coffee creator page with the `tannermleoy` handle, or update `.github/FUNDING.yml` and `SupportLinks.swift` if you choose a different handle.
- In the GitHub repository settings, enable Sponsorships so GitHub displays the Sponsor button from `.github/FUNDING.yml`.

## Run Locally

Run the Swift package executable directly for app-only development:

```sh
swift run SunStatus
```

For widget development, use the Xcode-backed app bundle path:

```sh
script/build_and_run.sh --verify --demo --pin --angled-map
```

To install the development build into `/Applications` and register the widget extension from the same location users install from:

```sh
script/build_and_run.sh --install --verify
```

You can also open `SunStatus.xcodeproj` and run the `SunStatus` scheme in Xcode. The app target embeds the `SunStatusWidgetExtension` target under `Contents/PlugIns`.

## Widget Development

Use Xcode for widget source, target, scheme, and layout development:

1. Open `SunStatus.xcodeproj`.
2. Open `Sources/SunStatus/Views/SunStatusWidgetCanvasPreview.swift` to preview the small, medium, and large widget layouts in Xcode's canvas.
3. Open `Sources/SunStatusWidgetExtension/SunStatusWidget.swift` for the real WidgetKit extension entry points.
4. Build the `SunStatusWidgetExtension` scheme to catch compile-time widget issues.
5. Run the `SunStatusWidgetExtension` scheme from Xcode when you need WidgetKit host debugging.
6. Install a local app build with `script/build_and_run.sh --install --verify`, then add SunStatus from the macOS widget gallery.

On macOS, Xcode may show `This platform does not support previewing widgets` for `#Preview(as: .systemSmall)` previews inside the `.appex` target. Use the app-target canvas preview file for in-Xcode visual iteration, then verify the real WidgetKit extension in the system widget gallery after installing and launching the containing app. Bump the app/widget version when adding or removing widget configurations so `chronod` refreshes the widget descriptor.

Before relying on the gallery, run:

```sh
scripts/verify-widgets.sh
```

This builds the widget extension target, builds the host app, verifies the embedded `.appex`, and checks signing/metadata. It does not replace visual inspection in Xcode or the macOS widget gallery, because WidgetKit does not provide a terminal renderer for widget pixels.

Useful local flags:

- `--pin` opens the pinned widget window.
- `--map` or `--expanded-map` opens the expanded map window.
- `--demo` uses deterministic demo status data.
- `--readme-screenshots` or `--generic-location` prevents the map from following or displaying the machine's current location.
- `--angled-map`, `--wide-map`, and `--close-map` adjust the launch camera for visual QA.

## Test

```sh
swift test
```

## Build Release Artifacts

Build release artifacts locally:

```sh
scripts/build-release.sh 0.4.1
```

The script outputs `.build/release/SunStatus.zip` and `.build/release/SunStatus.dmg`, builds the Xcode app and WidgetKit extension targets, embeds the extension, generates `Resources/AppIcon.icns` from `Assets/AppIcon.png`, codesigns the bundle ad hoc, mounts and verifies the DMG contents, and prints SHA-256 checksums.

After building a release locally, update the Homebrew cask with the DMG checksum:

```sh
scripts/update-homebrew-cask.sh 0.4.1 <SunStatus.dmg sha256>
```

Tagged GitHub releases publish `.zip`, `.dmg`, `SHA256SUMS`, and a cask patch. The `discolotus/homebrew-sunstatus` tap also runs an hourly sync that updates the cask from the latest SunStatus release. For immediate tap updates after a release, configure the `HOMEBREW_TAP_TOKEN` repository secret with a fine-grained GitHub token for `discolotus/homebrew-sunstatus` that has Actions read/write permission.

## App Icon

The source app icon is tracked at `Assets/AppIcon.png`. The Xcode app target generates the required `.icns` bundle resource from that image during the build, and the app bundle sets `CFBundleIconFile` to `AppIcon`.

## Project Status

SunStatus is preparing a map-focused release candidate. The core app, real astronomy engine, current-location support, Open-Meteo weather enrichment, MapKit 3D overlays, zip/DMG release script, Homebrew cask template, tap sync workflow, and test suite are in place. Remaining distribution work is mainly Developer ID signing and notarization.

See [CHANGELOG.md](CHANGELOG.md) for release notes and [ROADMAP.md](ROADMAP.md) for the longer implementation plan.
