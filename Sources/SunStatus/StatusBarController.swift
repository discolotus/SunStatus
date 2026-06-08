import AppKit
import SwiftUI
import SunStatusCore

@MainActor
final class StatusBarController: NSObject, NSPopoverDelegate {
    private let provider: DaylightProviding
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private var timer: Timer?

    init(provider: DaylightProviding) {
        self.provider = provider
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.popover = NSPopover()
        super.init()

        configurePopover()
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
        button.target = self
        button.action = #selector(togglePopover)
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.delegate = self
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

        if popover.isShown {
            popover.contentViewController = makePopoverController(for: status)
        }
    }

    @objc private func togglePopover() {
        guard let button = statusItem.button else {
            return
        }

        if popover.isShown {
            popover.performClose(nil)
            return
        }

        let status = provider.status(at: .now)
        popover.contentViewController = makePopoverController(for: status)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    private func makePopoverController(for status: DaylightStatus) -> NSViewController {
        let view = SunStatusPopoverView(
            status: status,
            onOpenSettings: { [weak self] in
                self?.popover.performClose(nil)
                (NSApp.delegate as? AppDelegate)?.showSettingsWindow()
            },
            onQuit: {
                NSApp.terminate(nil)
            }
        )

        return NSHostingController(rootView: view)
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

}
