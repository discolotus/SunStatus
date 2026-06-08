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
- Eventually support scrubbed time-of-day interaction so users can preview shadow angles.

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
  - Hosts MapKit satellite/3D map presentation.
  - Converts solar azimuth/elevation into a visible path and shadow direction overlay.
  - Remains optional until the simpler daylight UI is reliable.

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
- [x] Define minimum supported macOS version: macOS 14+ for the first SwiftUI `MenuBarExtra` implementation.
- [x] Decide whether to scaffold with a plain Swift Package plus app target or a standard Xcode project: start with a Swift Package app target for fast local iteration, defer app bundle/signing details to distribution prep.
- [x] Establish branch naming, formatting, and test conventions: use `codex/` feature branches, Swift Package defaults, and focused XCTest coverage for deterministic core logic.

### 1. Simple Native Menu Bar App

- [x] Scaffold a macOS Swift app.
- [x] Add a menu bar item using native APIs.
- [x] Open a SwiftUI popover when clicked.
- [x] Render placeholder sun position states with mock data.
- [x] Add a lightweight settings/about surface.

### 2. Astronomy Engine

- Implement sunrise and sunset calculations for a date and coordinate.
- Compute solar elevation, azimuth, solar noon, and daylight progress.
- Add unit tests for representative locations, including polar-day and polar-night edge cases.
- Wire real astronomy data into the menu bar icon and popover arc.

### 3. Location Support

- Request CoreLocation authorization.
- Use current location when permission is granted.
- Show a clear fallback state when permission is denied.
- Add manual location selection as a later fallback if needed.

### 4. Brightness Forecast

- Integrate weather data through a provider abstraction.
- Fetch current and hourly cloud cover, UV index, visibility, and condition signals.
- Build the perceived brightness score.
- Render the brightness line along the solar arc.
- Explain brightness modifiers in short labels.

### 5. Menu Bar Icon Polish

- Build multiple compact icon variants for day, night, sunrise, sunset, cloudy, hazy, and bright states.
- Ensure the icon remains legible in light mode, dark mode, and high-contrast settings.
- Tune update frequency for accuracy without wasting energy.

### 6. 3D Map and Sun Path

- Add a MapKit-based satellite view.
- Center on the user's current location by default.
- Allow pan, zoom, pitch, and location selection.
- Overlay the sun path in 3D space.
- Show current sun vector and approximate shadow direction.
- Add a time scrubber for previewing future shadow angles.

### 7. Preferences and Reliability

- Add settings for units, default location behavior, update interval, and menu bar display style.
- Cache recent weather and astronomy results.
- Add robust offline and permission-denied states.
- Add accessibility labels and keyboard navigation.

### 8. Distribution Prep

- Add app icon, signing configuration, and release build settings.
- Prepare privacy notes for location and weather usage.
- Add a lightweight onboarding flow for permissions.
- Evaluate direct distribution versus Mac App Store packaging.

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
