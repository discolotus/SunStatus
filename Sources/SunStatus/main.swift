import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = item.button {
            button.toolTip = "SunStatus"

            if let image = NSImage(systemSymbolName: "sun.max", accessibilityDescription: "SunStatus") {
                image.isTemplate = true
                button.image = image
            } else {
                button.title = "Sun"
            }
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "SunStatus", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Daylight tracking is coming soon.", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())

        let aboutItem = NSMenuItem(title: "About SunStatus", action: #selector(showAbout), keyEquivalent: "")
        aboutItem.target = self
        menu.addItem(aboutItem)

        let quitItem = NSMenuItem(title: "Quit SunStatus", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quitItem.target = NSApp
        menu.addItem(quitItem)

        item.menu = menu
        statusItem = item
    }

    @objc private func showAbout() {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"

        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "SunStatus",
            .applicationVersion: version,
            .credits: NSAttributedString(string: "A menu bar companion for daylight at a glance.")
        ])
        NSApp.activate(ignoringOtherApps: true)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()

app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
