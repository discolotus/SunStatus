import SwiftUI

struct SettingsView: View {
    @AppStorage("launchAtLogin") private var launchAtLogin = false
    @AppStorage("showCountdownInMenuBar") private var showCountdownInMenuBar = true
    @AppStorage("updateIntervalMinutes") private var updateIntervalMinutes = 5.0
    private let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.2.0"

    var body: some View {
        Form {
            Section {
                Toggle("Show countdown in menu bar", isOn: $showCountdownInMenuBar)
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
                LabeledContent("Version", value: version)
                LabeledContent("Data", value: "Mock daylight")
            } header: {
                Text("About")
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 420, height: 280)
    }
}
