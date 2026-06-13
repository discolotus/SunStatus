import AppKit
import SwiftUI
#if canImport(SunStatusCore)
import SunStatusCore
#endif

@main
enum SunStatusMain {
    static func main() {
        guard !AppDelegate.shouldActivateExistingInstanceAndExit else {
            return
        }

        let app = NSApplication.shared
        let delegate = AppDelegate()
        AppDelegate.shared = delegate

        app.delegate = delegate
        app.setActivationPolicy(AppDelegate.shouldUseRegularActivationPolicy ? .regular : .accessory)
        app.run()
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    fileprivate static var shared: AppDelegate?
    private static let showDockIconKey = "showDockIcon"
    private static let cloudShiftArguments = ["--cloud-shift", "--demo-cloud-shift"]

    private var statusController: StatusBarController?
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusController = StatusBarController(provider: Self.makeProvider())

        if Self.shouldOpenPinnedWindowAtLaunch {
            statusController?.showPinnedWindow()
        }

        if Self.shouldOpenExpandedMapAtLaunch {
            statusController?.showExpandedMapWindow()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func showSettingsWindow() {
        if settingsWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 500, height: 560),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = "SunStatus Settings"
            window.center()
            window.contentViewController = NSHostingController(rootView: SettingsView())
            window.setContentSize(NSSize(width: 500, height: 560))
            settingsWindow = window
        }

        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    static func setShowsDockIcon(_ showsDockIcon: Bool) {
        NSApp.setActivationPolicy(showsDockIcon ? .regular : .accessory)

        if showsDockIcon {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    fileprivate static var shouldActivateExistingInstanceAndExit: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        guard !arguments.contains("--allow-multiple-instances") else {
            return false
        }

        guard let bundleIdentifier = Bundle.main.bundleIdentifier else {
            return false
        }

        let currentProcessIdentifier = ProcessInfo.processInfo.processIdentifier
        guard let existingApplication = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleIdentifier)
            .first(where: { $0.processIdentifier != currentProcessIdentifier && !$0.isTerminated })
        else {
            return false
        }

        existingApplication.activate(options: [])
        return true
    }

    fileprivate static var shouldUseRegularActivationPolicy: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        return UserDefaults.standard.bool(forKey: showDockIconKey)
            || arguments.contains("--pin")
            || arguments.contains("--window")
            || arguments.contains("--map")
            || arguments.contains("--expanded-map")
    }

    private static var shouldOpenPinnedWindowAtLaunch: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        return arguments.contains("--pin")
    }

    private static var shouldOpenExpandedMapAtLaunch: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        return arguments.contains("--window") || arguments.contains("--map") || arguments.contains("--expanded-map")
    }

    private static func makeProvider() -> DaylightProviding {
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains(where: cloudShiftArguments.contains) {
            return CloudShiftDaylightProvider()
        }

        if arguments.contains("--mock") || arguments.contains("--demo") {
            return MockDaylightProvider(locationName: "San Francisco")
        }

        return LocationAwareDaylightProvider()
    }
}

private struct CloudShiftDaylightProvider: DaylightProviding {
    func status(at _: Date) -> DaylightStatus {
        SunStatusPreviewFixtures.brightMorningCloudyAfternoonStatus
    }
}
