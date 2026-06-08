# Changelog

All notable changes to SunStatus will be documented in this file.

## [0.3.0] - 2026-06-08

### Added

- Added a MapKit-backed 3D satellite/elevation map prototype with sun path, current sun vector, and shadow-bearing overlays.
- Added CoreLocation-backed current-location centering with a clear San Francisco fallback when location is pending, denied, restricted, or unavailable.
- Added GitHub Actions CI for Swift tests and a version/changelog guard.
- Added a GitHub Actions release workflow that publishes a release archive when the default release version changes on `main`.

### Changed

- Kept the SceneKit sun-path model as a companion `Model` view beside the new `Map` view.
- Moved model cardinal direction labels into SceneKit world space so they move with camera orbit instead of staying fixed on screen.
- Added macOS location usage descriptions to generated release bundles.
- Hardened release signing by clearing extended attributes before `codesign`.

### Notes

- The 3D map still uses mock astronomy data; real coordinate-correct solar calculations remain a follow-up before the overlay should be treated as physically trustworthy.
