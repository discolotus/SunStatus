import AppKit
import SwiftUI
import SunStatusCore

@main
enum SunStatusMain {
    static func main() {
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
                contentRect: NSRect(x: 0, y: 0, width: 420, height: 420),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = "SunStatus Settings"
            window.center()
            window.contentViewController = NSHostingController(rootView: SettingsView())
            window.setContentSize(NSSize(width: 420, height: 420))
            settingsWindow = window
        }

        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    fileprivate static var shouldUseRegularActivationPolicy: Bool {
        let arguments = ProcessInfo.processInfo.arguments
        return arguments.contains("--pin")
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
        if arguments.contains("--mock") || arguments.contains("--demo") {
            return MockDaylightProvider(locationName: "San Francisco")
        }

        return LocationAwareDaylightProvider()
    }
}
