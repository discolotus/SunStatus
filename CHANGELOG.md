# Changelog

All notable changes to SunStatus will be documented in this file.

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
