# SunStatus Roadmap

## Product Vision

SunStatus is a macOS-native menu bar companion for people who care about daylight quality, not just weather. It should answer three questions quickly:

- Where is the sun in its arc right now?
- How long until the next major daylight transition, such as sunrise, golden hour, solar noon, or sunset?
- How bright will it actually feel outside, given cloud cover, fog, smoke, UV index, and time of day?

The primary interaction model is a menu bar item with a compact live icon. Clicking the icon opens a richer popover with detailed daylight information and, later, a 3D location view.

## Guiding Principles

- Prefer native macOS technologies: Swift, SwiftUI, AppKit where needed, MapKit, CoreLocation, and WeatherKit when available.
- Make the menu bar icon useful on its own. It should not just be a launcher.
- Treat "sun brightness" as a perceived-light estimate, not only an astronomical value.
- Keep weather, astronomy, and rendering logic separated so each can be tested independently.
- Degrade gracefully when location, network, or weather permissions are unavailable.
- Respect privacy by keeping precise location local unless a user-enabled weather provider requires a request.

## Target Experience

### Collapsed Menu Bar Item

- Show a compact icon representing the sun's position across the day.
- Encode progress from sunrise to sunset as an arc or horizon-relative position.
- Communicate urgency near sunset or sunrise with subtle visual state changes.
- Update automatically without user interaction.
- Offer a fallback state for night, missing location, or unavailable data.

### Expanded Popover

- Display a large sun icon whose style can reflect UV index, perceived brightness, cloud cover, fog, or smoke.
- Draw a solar arc above or around the sun.
- Fill the completed portion of the arc and outline the future portion.
- Draw a second brightness line along the same arc:
  - Very light gray means bright conditions.
  - Darker gray means clouds, fog, smoke, or dim conditions.
- Show sunrise time under the left end of the arc.
- Show sunset time under the right end of the arc.
- Include concise current-state readouts such as time until sunset, UV index, cloud cover, visibility, and brightness classification.

### 3D Sun Path View

- Show a 3D satellite map centered on the user's current location by default.
- Let the user pan, drag, zoom, pitch, and inspect another location.
- Overlay the sun's path through 3D space for the selected day and selected map location.
- Show the current sun vector and approximate shadow direction.
- Support scrubbed time-of-day interaction so users can preview shadow angles.

### Apple Maps 3D Implementation Plan

Apple Maps integration should be built in phases because public MapKit APIs can provide realistic satellite/elevation maps and map overlays, but they do not expose editable 3D satellite/building mesh geometry to SceneKit.

- Phase 1: Add a MapKit-backed satellite view using realistic elevation, centered on the selected coordinate, and draw map-projected sun path, current sun vector, and shadow bearing overlays from the existing `SunPathSample3D` data. Completed for current-location and demo coordinates.
- Phase 2: Add CoreLocation-backed centering and map selection so the overlay recomputes for the user's current or inspected coordinate. Current-location recompute is complete; manual inspected-coordinate selection remains open.
- Phase 3: Synchronize the existing SceneKit sky-dome model with the MapKit camera heading and pitch, keeping the SceneKit prototype as the precision visualization layer.
- Phase 4: Research building-aware shadows only after the useful MapKit overlay is working. If true occlusion or building-height shadows become essential, evaluate non-MapKit sources such as OSM building extrusions, 3D tiles, Mapbox, Cesium, or ArcGIS.
- MVP success: users can open the 3D tab, see real satellite/elevation context, scrub time, and understand the sun bearing and approximate surface shadow direction over the selected map location.

## Architecture

### App Shell

- Build as a Swift macOS app.
- Use `MenuBarExtra` for modern menu bar presence when possible.
- Use a SwiftUI popover for the expanded view.
- Use AppKit bridges only where SwiftUI does not expose enough control over status item rendering or popover behavior.

### Core Modules

- `AstronomyCore`
  - Calculates sunrise, sunset, solar noon, golden hour candidates, solar elevation, solar azimuth, and daylight progress.
  - Owns deterministic tests for date, latitude, longitude, and timezone scenarios.

- `WeatherCore`
  - Fetches current and hourly forecast data.
  - Normalizes provider values for cloud cover, visibility, UV index, fog, smoke, precipitation, and condition codes.
  - Starts with WeatherKit where possible, with a provider interface for future fallbacks.

- `BrightnessModel`
  - Combines solar elevation, cloud cover, visibility, UV index, fog, smoke, and precipitation into a perceived brightness score.
  - Produces both current brightness and an hourly/day-arc forecast.
  - Keeps the model explainable so UI labels can say why conditions are bright, hazy, dim, or muted.

- `LocationCore`
  - Requests and stores user permission state.
  - Provides current location and selected map location.
  - Supports manual fallback location entry later.

- `SunStatusUI`
  - Renders the menu bar icon, popover arc, brightness path, current status, and settings.
  - Keeps visual components previewable with mock data.

- `SunMap3D`
  - Hosts MapKit satellite/realistic-elevation map presentation.
  - Converts solar azimuth/elevation into visible map-projected path, sun vector, and shadow direction overlays.
  - Keeps the SceneKit model as a precision sky-dome companion rather than depending on MapKit to expose editable 3D mesh data.
  - Remains optional until location, astronomy, and simpler daylight UI are reliable.

## Data Model Sketch

```swift
struct SolarSnapshot {
    let date: Date
    let location: Coordinate
    let sunrise: Date?
    let solarNoon: Date?
    let sunset: Date?
    let elevationDegrees: Double
    let azimuthDegrees: Double
    let daylightProgress: Double?
}

struct BrightnessSnapshot {
    let date: Date
    let score: Double
    let classification: BrightnessClassification
    let cloudCover: Double?
    let uvIndex: Int?
    let visibilityMeters: Double?
    let modifiers: [BrightnessModifier]
}

struct SunArcPoint {
    let date: Date
    let progress: Double
    let elevationDegrees: Double
    let azimuthDegrees: Double
    let brightnessScore: Double?
}
```

## Milestones

### 0. Project Foundation

- [x] Create the repository, roadmap, and basic project documentation.
- [x] Define minimum supported macOS version: macOS 14+ for the first SwiftUI/AppKit menu bar implementation.
- [x] Decide whether to scaffold with a plain Swift Package plus app target or a standard Xcode project: start with a Swift Package app target for fast local iteration, defer app bundle/signing details to distribution prep.
- [x] Establish branch naming, formatting, and test conventions: use `codex/` feature branches, Swift Package defaults, and focused XCTest coverage for deterministic core logic.

### 1. Simple Native Menu Bar App

- [x] Scaffold a macOS Swift app.
- [x] Add a menu bar item using native APIs.
- [x] Open a SwiftUI popover when clicked.
- [x] Render placeholder sun position states with mock data.
- [x] Add a lightweight settings/about surface.

### 2. Astronomy Engine

- [x] Implement sunrise and sunset calculations for a date and coordinate.
- [x] Compute solar elevation, azimuth, solar noon, and daylight progress.
- [x] Add unit tests for representative locations, including polar-day and polar-night edge cases.
- [x] Wire real astronomy data into the menu bar icon and popover arc.

Implemented in `SolarPositionCalculator` (NOAA / Meeus solar position algorithm) and surfaced
through `SolarDaylightProvider`, which replaces the sine-curve `MockDaylightProvider` on the
production path. `MockDaylightProvider` is retained for SwiftUI previews and fixtures.

### 3. Location Support

- [x] Request CoreLocation authorization.
- [x] Use current location when permission is granted.
- [x] Show a clear fallback state when permission is denied.
- Add manual location selection as a later fallback if needed.

### 4. Brightness Forecast

- [x] Integrate weather data through a provider abstraction.
- [x] Fetch current and hourly cloud cover, UV index, and visibility.
- [x] Build the perceived brightness score.
- [x] Render cloud/brightness variation along the solar arc.
- [x] Explain brightness modifiers in short labels.
- Add richer condition signals such as fog, smoke, air quality, and precipitation when a provider supports them.

### 5. Menu Bar Icon Polish

- Build multiple compact icon variants for day, night, sunrise, sunset, cloudy, hazy, and bright states.
- Ensure the icon remains legible in light mode, dark mode, and high-contrast settings.
- Tune update frequency for accuracy without wasting energy.

### 6. 3D Map and Sun Path

- [x] Add a MapKit-based satellite/realistic-elevation prototype view.
- [x] Overlay real map-projected sun path, current sun vector, shadow bearing, and dashed ground projections.
- [x] Center on the user's current location by default when CoreLocation is authorized.
- [ ] Recompute the overlay for a user-selected map coordinate.
- [x] Keep the SceneKit sky-dome model available as a companion precision view.
- [x] Move model cardinal labels into SceneKit world space so they shift with camera orbit.
- [ ] Synchronize SceneKit overlay orientation with MapKit camera heading/pitch.
- [ ] Research building-aware shadows and 3D tiles only after the MapKit overlay MVP is useful.
- [x] Add a native SceneKit 3D sun-angle prototype in the popover.
- [x] Allow orbit/zoom inspection in the SceneKit prototype.
- [x] Overlay the real sun path in 3D space.
- [x] Show current sun vector and approximate shadow direction.
- [x] Add a time scrubber for previewing future shadow angles.

### 7. Preferences and Reliability

- Add settings for units, default location behavior, update interval, and menu bar display style.
- Cache recent weather and astronomy results.
- Add robust offline and permission-denied states.
- Add accessibility labels and keyboard navigation.

### 8. Homebrew Distribution Prep

- [x] Add app icon and release build settings.
- [x] Prepare privacy notes for location and weather usage.
- Add a lightweight onboarding flow for permissions.
- Produce a signed and notarized macOS release artifact suitable for direct distribution.
- [x] Produce an installable `.dmg` artifact with `SunStatus.app` and an Applications shortcut.
- [x] Attach both `.zip` and `.dmg` artifacts to GitHub releases when a release version lands on `main`.
- [x] Add release workflow checks that verify the `.dmg` mounts, contains the expected app bundle, and preserves the generated version metadata.
- Decide whether the Homebrew cask should continue to use the `.zip` archive or switch to the `.dmg` once notarization is in place.
- Create release archives with stable version tags and checksums.
- [x] Add a Homebrew cask formula that installs the app from the release artifact.
- Publish the Homebrew tap and keep the cask checksum updated for each release.
- Document the install command, update flow, and uninstall command for users.

### 9. DMG and Notarized Distribution

- [x] Add a repeatable DMG creation script using native macOS tooling such as `hdiutil`.
- [x] Include `SunStatus.app`, an Applications folder shortcut, and a simple polished volume name.
- Add Developer ID signing configuration for release builds.
- Add Apple notarization and stapling steps once credentials are available in CI.
- [x] Update the GitHub release workflow to upload the `.dmg` alongside the existing `.zip`.
- [x] Add CI validation that mounts the generated DMG, confirms the version metadata, and inspects the app bundle without modifying user state.
- [x] Document direct-download install steps and expected Gatekeeper behavior.
- Keep Homebrew distribution working while adding the friendlier DMG path for non-Homebrew users.

## Immediate Next Steps

The 3D map MVP is now usable for release-candidate review:

- [x] Add a MapKit-backed satellite/realistic-elevation panel to the existing 3D tab.
- [x] Reuse `SunPathSample3D` and map-project the path, selected sun vector, and shadow bearing around the selected coordinate.
- [x] Preserve the existing SceneKit prototype as a model view for sun-angle inspection.
- [x] Add real astronomy data before treating the MapKit overlay as physically trustworthy. The overlay now reads from `SolarPositionCalculator`.
- [x] Recenter the compact widget and expanded map around the current location, including solar geometry and weather refresh.
- [x] Add Mercator-aware correction, projected ground overlays, and compact camera orbit with an interaction pause.
- Synchronize the SceneKit model orientation with the MapKit camera heading and pitch if the model view remains a first-class release surface.
- Recompute the overlay for a user-selected map coordinate rather than only the current location.

Distribution work remains queued after the current map slice:

- Decide production signing/notarization setup.
- [x] Add a repeatable release build process that outputs an ad-hoc signed `.app` inside a versioned archive.
- [x] Add a repeatable DMG build process that packages the app as a direct macOS install artifact.
- [x] Update the release workflow so version bumps on `main` attach the DMG artifact as well as the zip archive.
- [x] Validate DMG mount, app bundle contents, version metadata, and install flow in CI.
- Tag releases consistently so Homebrew can target immutable download URLs.
- Create or update the Homebrew tap, expected as `discolotus/homebrew-sunstatus` for the documented `discolotus/sunstatus/sunstatus` install command.
- [x] Add a `Casks/sunstatus.rb` cask that points to the DMG release archive and verifies its SHA-256 checksum.
- [x] Update the README with the Homebrew installation command and direct DMG install notes.
- Validate install, launch, upgrade, and uninstall behavior locally through Homebrew.

## First Feature Branch Scope

The first implementation branch should stay focused on the simple surface:

- [x] Scaffold the native macOS app.
- [x] Add the menu bar item.
- [x] Add an expanded popover.
- [x] Draw a mock solar arc with sunrise and sunset labels.
- [x] Use mock brightness samples along the arc.
- [x] Leave real location, weather, and 3D map work for later branches.

Recommended branch name: `codex/menu-bar-foundation`.

## Open Questions

- What is the minimum macOS version target?
- Should the app be App Store-ready from the beginning, or is direct local distribution acceptable during early development?
- Which weather fallback should be used if WeatherKit does not expose enough smoke, fog, or air-quality signal for the brightness model?
- Should manual location selection be available before or after current-location support?
- How visually detailed should the menu bar icon be versus the expanded popover?

## Early Risks

- Menu bar icons have limited space, so the collapsed visualization may need several iterations to remain legible.
- Weather data may not map cleanly to perceived brightness, especially for smoke and haze.
- The 3D sun path overlay may require custom rendering around MapKit limitations.
- Polar day, polar night, timezone boundaries, and daylight saving changes need explicit test coverage.
- Location and weather permissions must be handled without making the app feel broken.
