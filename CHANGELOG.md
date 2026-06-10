# Changelog

All notable changes to SunStatus will be documented in this file.

## [Unreleased]

## [0.4.0] - 2026-06-10

### Added

- Added a compact and expanded MapKit 3D sun-path experience centered on the user's current location by default.
- Added Mercator-aware map projection correction for the 3D arc overlay so panning the Apple Maps camera no longer distorts the sun path relative to the selected coordinate.
- Added dashed 2D ground projections for the full sun path and current sun direction, matching opacity across both projection overlays.
- Added compact-widget camera orbit around the user's current location, with automatic 30-second pause when the user clicks, drags, scrolls, or uses keyboard input inside the map.
- Added selected-current-location weather refreshes so the widget arc keeps real cloud-cover detail when the map recenters on the user.
- Added coordinate-aware weather caching and a wider two-day hourly Open-Meteo cloud-cover forecast window.
- Added interpolation between hourly cloud-cover samples so the arc renders smoother cloud gradients.
- Added README screenshots for the widget and expanded 3D map.
- Added app-icon generation to the local `script/build_and_run.sh` dev bundle path, matching the release bundle's `AppIcon.icns` metadata.
- Added a `--readme-screenshots` / `--generic-location` launch flag so documentation captures can use the generic demo coordinate without showing the user's real location.
- Added a release DMG artifact containing `SunStatus.app` and an Applications shortcut, with build-script verification that mounts the DMG and checks the copied app bundle.
- Added a Homebrew cask template for the DMG release artifact and a helper script for updating its version and SHA-256 checksum after building a release.
- Added GitHub Sponsors and Buy Me a Coffee donation metadata plus in-app Settings support links.
- Added `SolarPositionCalculator`, a real solar-position engine implementing the NOAA / Meeus algorithm. It computes refraction-corrected solar elevation and azimuth for any instant, plus sunrise, solar noon, and sunset for any date and coordinate, including polar-day and polar-night handling.
- Added `SolarDaylightProvider`, a `DaylightProviding` implementation backed by the new engine. It generates coordinate-correct solar snapshots and sampled sun-path arc points, with a clear-sky, elevation-driven brightness heuristic.
- Added unit tests covering declination at the solstices and equinoxes, solar-noon geometry, sunrise/sunset symmetry, output ranges, and polar edge cases.

### Changed

- Bumped the default release version from `0.3.0` to `0.4.0`.
- The expanded map window now uses a centered `SunStatus` title, removes the extra in-page map header, and keeps the map flush near the top of the window.
- Compact and expanded 3D map camera presets were tuned separately so the widget stays close, pitched, and readable while the expanded view provides more room for inspection.
- The status model now rebuilds around the selected current-location coordinate when MapKit reports the user's location, keeping the location text, solar geometry, cloud data, and map overlay in sync.
- The shadow projection line now matches the projected sun-direction length and uses the same dashed, lower-opacity styling as the 2D projection overlays.
- Preview-time scrubbing now keeps static MapKit ground overlays installed and only refreshes the selected-time overlays, reducing projection-line lag while moving the time slider.
- The dashed ground sun-path projection now uses the same yellow hue as the 3D sun path, compact widget projection lines are slightly thicker, and the location rings are generated as projected terrain polylines.
- GitHub releases now upload both `.zip` and `.dmg` artifacts when a version bump lands on `main`.
- Generated `dist/` app bundles are now ignored by git.
- `LocationAwareDaylightProvider` now uses `SolarDaylightProvider` instead of the sine-curve `MockDaylightProvider`, so the menu bar arc, popover readouts, and 2D/3D sun-path overlays are driven by real astronomy and can be treated as physically trustworthy. `MockDaylightProvider` is retained for SwiftUI previews and test fixtures.

### Notes

- MapKit still does not expose editable Apple Maps 3D mesh geometry or building-aware occlusion, so the 3D map visualizes sun path, sun direction, and approximate surface shadow direction rather than true mesh shadow casting.

## [0.3.0] - 2026-06-08

### Added

- Added a MapKit-backed `Map` mode to the 3D panel using satellite imagery with realistic elevation, pitch, rotation, zoom, compass, and zoom controls.
- Added map-projected overlays for the daily sun path, a horizon reference ring, the selected sun vector, the selected shadow-bearing vector, and a center marker at the selected coordinate.
- Added a `Model` mode beside the new map so the existing SceneKit sun-path visualization remains available for precise angle inspection.
- Added a shared 3D time scrubber that updates the selected sample, map overlay vectors, angle readouts, and model view.
- Added CoreLocation authorization and one-shot location lookup through `LocationAwareDaylightProvider`.
- Added current-location centering for the status data and 3D map when location permission is granted.
- Added clear location fallback labels for locating, denied, restricted, and unavailable states while preserving the San Francisco mock-data fallback.
- Added macOS location usage descriptions to generated release bundles so the app can request location permission.
- Added `CHANGELOG.md` as the release-note source for versioned releases.
- Added GitHub Actions CI for Swift tests.
- Added a PR version/changelog guard that fails when the release version changes without a matching changelog entry.
- Added a GitHub Actions release workflow that detects release-version bumps on `main`, runs tests, builds the release archive, extracts matching changelog notes, and creates a GitHub release.

### Changed

- Bumped the default release version from `0.2.4` to `0.3.0`.
- Updated README status and build examples for the 3D map prototype and `0.3.0` release.
- Updated the roadmap with the phased Apple Maps implementation plan, current 3D progress, CoreLocation progress, and remaining map/release work.
- Reworked the 3D panel to default to the MapKit map while preserving the SceneKit model under a segmented `Map` / `Model` control.
- Moved model cardinal direction labels into SceneKit world space so `N`, `E`, `S`, and `W` move with camera orbit instead of staying fixed on screen.
- Refreshed status-item and popover content immediately when CoreLocation state changes instead of waiting for the next timer tick.
- Hardened release signing by clearing extended attributes before `codesign`.
- Updated the generated release archive path to include location permission metadata in `Info.plist`.

### Notes

- The 3D map still uses mock astronomy data for sunrise, sunset, solar elevation, and solar azimuth. Real coordinate-correct solar calculations remain a follow-up before the overlay should be treated as physically trustworthy.
- The release workflow currently attaches the existing `.zip` app archive. A DMG artifact, Developer ID signing, and notarization are now tracked in the roadmap for the next distribution pass.
- The 3D map overlays are MapKit overlays projected around the selected coordinate. They do not perform building-aware occlusion or true 3D mesh shadow casting.
