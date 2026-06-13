import AppKit
import CoreLocation
import SwiftUI

struct SettingsView: View {
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("showDockIcon") private var showDockIcon = false
    @AppStorage("showCountdownInMenuBar") private var showCountdownInMenuBar = true
    @AppStorage("updateIntervalMinutes") private var updateIntervalMinutes = 5.0
    @AppStorage("useManualLocation") private var useManualLocation = false
    @AppStorage("manualLocationQuery") private var manualLocationQuery = ""
    @AppStorage("manualLocationName") private var manualLocationName = ""
    @AppStorage("manualLocationLatitude") private var manualLocationLatitude = 0.0
    @AppStorage("manualLocationLongitude") private var manualLocationLongitude = 0.0
    @AppStorage("manualLocationTimeZoneIdentifier") private var manualLocationTimeZoneIdentifier = ""
    @AppStorage("manualLocationIsSet") private var manualLocationIsSet = false

    @State private var isResolvingManualLocation = false
    @State private var manualLocationStatus = ""

    private let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.2.4"

    var body: some View {
        Form {
            Section {
                Toggle("Show countdown in menu bar", isOn: $showCountdownInMenuBar)
                Toggle("Show app icon in Dock while running", isOn: $showDockIcon)
                Toggle("Launch at login", isOn: $launchAtLogin)

                VStack(alignment: .leading) {
                    Text("Update interval")
                    Slider(value: $updateIntervalMinutes, in: 1...30, step: 1) {
                        Text("Update interval")
                    } minimumValueLabel: {
                        Text("1m")
                    } maximumValueLabel: {
                        Text("30m")
                    }

                    Text("\(Int(updateIntervalMinutes)) minutes")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Menu Bar")
            }

            Section {
                Toggle("Use manual location", isOn: $useManualLocation)

                VStack(alignment: .leading, spacing: 8) {
                    TextField("City, address, or 37.7749, -122.4194", text: $manualLocationQuery)

                    HStack {
                        Button {
                            resolveManualLocation()
                        } label: {
                            Label(isResolvingManualLocation ? "Resolving" : "Resolve", systemImage: "location.magnifyingglass")
                        }
                        .disabled(isResolvingManualLocation || manualLocationQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        Button("Clear") {
                            clearManualLocation()
                        }
                        .disabled(!manualLocationIsSet && manualLocationQuery.isEmpty)

                        Spacer()
                    }

                    if !manualLocationStatus.isEmpty {
                        Text(manualLocationStatus)
                            .font(.caption)
                            .foregroundStyle(Color(nsColor: manualLocationIsSet ? .secondaryLabelColor : .systemRed))
                    }

                    if manualLocationIsSet {
                        Text("\(manualLocationName) - \(coordinateText)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            } header: {
                Text("Location")
            } footer: {
                Text("Automatic mode uses macOS location services. Manual mode uses the saved location above for the menu bar, popover, windows, and weather.")
            }

            Section {
                LabeledContent("Version", value: version)
                LabeledContent("Location", value: useManualLocation && manualLocationIsSet ? manualLocationName : "Automatic")

                Link(destination: SupportLinks.githubSponsorsURL) {
                    Label("Sponsor on GitHub", systemImage: "heart.fill")
                }

                Link(destination: SupportLinks.buyMeACoffeeURL) {
                    Label("Buy Me a Coffee", systemImage: "cup.and.saucer.fill")
                }
            } header: {
                Text("About")
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 500)
        .frame(minHeight: 560)
        .onAppear {
            updateManualLocationStatus()
        }
        .onChange(of: showDockIcon) { _, newValue in
            AppDelegate.setShowsDockIcon(newValue)
        }
        .onChange(of: useManualLocation) { _, _ in
            updateManualLocationStatus()
            notifyManualLocationChanged()
        }
    }

    private var coordinateText: String {
        "\(String(format: "%.4f", manualLocationLatitude)), \(String(format: "%.4f", manualLocationLongitude))"
    }

    private func resolveManualLocation() {
        let query = manualLocationQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            manualLocationStatus = "Enter a city, address, or latitude and longitude."
            return
        }

        isResolvingManualLocation = true
        manualLocationStatus = "Resolving location..."

        if let coordinate = parseCoordinatePair(query) {
            storeManualLocation(
                name: query,
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
                timeZone: .current
            )
            return
        }

        CLGeocoder().geocodeAddressString(query) { placemarks, _ in
            Task { @MainActor in
                guard let placemark = placemarks?.first,
                      let location = placemark.location else {
                    isResolvingManualLocation = false
                    manualLocationIsSet = false
                    manualLocationStatus = "Location not found. Try a more specific city, address, or coordinates."
                    notifyManualLocationChanged()
                    return
                }

                storeManualLocation(
                    name: displayName(for: placemark, fallback: query),
                    latitude: location.coordinate.latitude,
                    longitude: location.coordinate.longitude,
                    timeZone: placemark.timeZone ?? .current
                )
            }
        }
    }

    private func storeManualLocation(name: String, latitude: Double, longitude: Double, timeZone: TimeZone) {
        manualLocationName = name
        manualLocationLatitude = latitude
        manualLocationLongitude = longitude
        manualLocationTimeZoneIdentifier = timeZone.identifier
        manualLocationIsSet = true
        useManualLocation = true
        isResolvingManualLocation = false
        manualLocationStatus = "Manual location saved."
        notifyManualLocationChanged()
    }

    private func clearManualLocation() {
        useManualLocation = false
        manualLocationQuery = ""
        manualLocationName = ""
        manualLocationLatitude = 0
        manualLocationLongitude = 0
        manualLocationTimeZoneIdentifier = ""
        manualLocationIsSet = false
        manualLocationStatus = "Automatic location enabled."
        notifyManualLocationChanged()
    }

    private func updateManualLocationStatus() {
        if useManualLocation && manualLocationIsSet {
            manualLocationStatus = "Manual location enabled."
        } else if manualLocationIsSet {
            manualLocationStatus = "Manual location saved but automatic location is enabled."
        } else {
            manualLocationStatus = "Automatic location enabled."
        }
    }

    private func parseCoordinatePair(_ value: String) -> (latitude: Double, longitude: Double)? {
        let parts = value
            .replacingOccurrences(of: ",", with: " ")
            .split(separator: " ")
            .map(String.init)

        guard parts.count == 2,
              let latitude = Double(parts[0]),
              let longitude = Double(parts[1]),
              (-90...90).contains(latitude),
              (-180...180).contains(longitude) else {
            return nil
        }

        return (latitude, longitude)
    }

    private func displayName(for placemark: CLPlacemark, fallback: String) -> String {
        let parts = [
            placemark.locality,
            placemark.administrativeArea,
            placemark.country
        ]
            .compactMap { $0 }
            .filter { !$0.isEmpty }

        if !parts.isEmpty {
            return parts.joined(separator: ", ")
        }

        return placemark.name ?? fallback
    }

    private func notifyManualLocationChanged() {
        NotificationCenter.default.post(name: .sunStatusManualLocationSettingsDidChange, object: nil)
    }
}

private extension Notification.Name {
    static let sunStatusManualLocationSettingsDidChange = Notification.Name("SunStatusManualLocationSettingsDidChange")
}

#if DEBUG
private enum SettingsViewPreviewData {
    @MainActor
    static let defaults: UserDefaults = {
        let defaults = UserDefaults(suiteName: "SunStatus.SettingsView.Previews") ?? .standard
        defaults.set(true, forKey: "showCountdownInMenuBar")
        defaults.set(false, forKey: "showDockIcon")
        defaults.set(false, forKey: "launchAtLogin")
        defaults.set(5.0, forKey: "updateIntervalMinutes")
        defaults.set(false, forKey: "useManualLocation")
        defaults.set("San Francisco, CA", forKey: "manualLocationQuery")
        defaults.set("San Francisco, CA, United States", forKey: "manualLocationName")
        defaults.set(37.7749, forKey: "manualLocationLatitude")
        defaults.set(-122.4194, forKey: "manualLocationLongitude")
        defaults.set("America/Los_Angeles", forKey: "manualLocationTimeZoneIdentifier")
        defaults.set(true, forKey: "manualLocationIsSet")
        return defaults
    }()
}

#Preview("Settings", traits: .sizeThatFitsLayout) {
    SettingsView()
        .defaultAppStorage(SettingsViewPreviewData.defaults)
}
#endif
