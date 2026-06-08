import AppKit
import SunStatusCore

@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    private let provider: DaylightProviding
    private let statusItem: NSStatusItem
    private let menu: NSMenu
    private var timer: Timer?

    init(provider: DaylightProviding) {
        self.provider = provider
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.menu = NSMenu()
        super.init()

        configureMenu()
        configureStatusButton()
        refresh()

        timer = Timer.scheduledTimer(
            timeInterval: 60,
            target: self,
            selector: #selector(refreshFromTimer),
            userInfo: nil,
            repeats: true
        )
    }

    private func configureStatusButton() {
        guard let button = statusItem.button else {
            assertionFailure("SunStatus status item did not create a button")
            return
        }

        button.image = NSImage(systemSymbolName: "sun.max.fill", accessibilityDescription: "SunStatus")
        button.image?.isTemplate = true
        button.imagePosition = .imageLeading
        button.toolTip = "SunStatus"
        statusItem.menu = menu
    }

    private func configureMenu() {
        menu.autoenablesItems = false
        menu.delegate = self
        rebuildMenu()
    }

    @objc private func refreshFromTimer() {
        refresh()
    }

    private func refresh() {
        let status = provider.status(at: .now)

        if let button = statusItem.button {
            button.title = menuTitle(for: status)
            button.setAccessibilityLabel(accessibilityLabel(for: status))
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        rebuildMenu()
    }

    private func rebuildMenu() {
        menu.removeAllItems()

        let status = provider.status(at: .now)

        let titleItem = NSMenuItem(title: "SunStatus", action: nil, keyEquivalent: "")
        titleItem.isEnabled = false
        menu.addItem(titleItem)

        menu.addItem(NSMenuItem.separator())

        let stateItem = NSMenuItem(title: statusLine(for: status), action: nil, keyEquivalent: "")
        stateItem.isEnabled = false
        menu.addItem(stateItem)

        let brightnessItem = NSMenuItem(
            title: "Brightness: \(Int(status.brightness.score * 100))% \(status.brightness.classification.displayName)",
            action: nil,
            keyEquivalent: ""
        )
        brightnessItem.isEnabled = false
        menu.addItem(brightnessItem)

        let sunriseItem = NSMenuItem(title: "Sunrise: \(timeText(status.solar.sunrise, timezone: status.timezone))", action: nil, keyEquivalent: "")
        sunriseItem.isEnabled = false
        menu.addItem(sunriseItem)

        let sunsetItem = NSMenuItem(title: "Sunset: \(timeText(status.solar.sunset, timezone: status.timezone))", action: nil, keyEquivalent: "")
        sunsetItem.isEnabled = false
        menu.addItem(sunsetItem)

        menu.addItem(NSMenuItem.separator())

        let settingsItem = NSMenuItem(title: "Settings...", action: #selector(openSettingsFromMenu), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let quitItem = NSMenuItem(title: "Quit SunStatus", action: #selector(quitFromMenu), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    @objc private func openSettingsFromMenu() {
        openSettings()
    }

    @objc private func quitFromMenu() {
        quit()
    }

    private func openSettings() {
        menu.cancelTracking()
        (NSApp.delegate as? AppDelegate)?.showSettingsWindow()
    }

    private func quit() {
        NSApp.terminate(nil)
    }

    private func menuTitle(for status: DaylightStatus) -> String {
        guard let transition = status.nextTransition else {
            return "Night"
        }

        let interval = max(transition.date.timeIntervalSince(status.solar.date), 0)
        let hours = Int(interval) / 3_600
        let minutes = (Int(interval) % 3_600) / 60

        if hours > 0 {
            return "\(hours)h"
        }

        return "\(max(minutes, 1))m"
    }

    private func accessibilityLabel(for status: DaylightStatus) -> String {
        guard let transition = status.nextTransition else {
            return "SunStatus, night"
        }

        return "SunStatus, \(transition.kind.displayName) in \(menuTitle(for: status))"
    }

    private func statusLine(for status: DaylightStatus) -> String {
        guard let transition = status.nextTransition else {
            return "Night mode until tomorrow"
        }

        return "\(menuTitle(for: status)) until \(transition.kind.displayName)"
    }

    private func timeText(_ date: Date?, timezone: TimeZone) -> String {
        guard let date else {
            return "--:--"
        }

        let formatter = DateFormatter()
        formatter.timeZone = timezone
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
