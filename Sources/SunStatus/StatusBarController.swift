import AppKit
import SwiftUI
import SunStatusCore

@MainActor
final class StatusBarController: NSObject, NSPopoverDelegate, NSWindowDelegate {
    private let provider: DaylightProviding
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private var pinnedWindow: NSWindow?
    private var expandedMapWindow: NSWindow?
    private var timer: Timer?

    init(provider: DaylightProviding) {
        self.provider = provider
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.popover = NSPopover()
        super.init()

        configurePopover()
        configureStatusButton()
        configureProviderUpdates()
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

    private func configureProviderUpdates() {
        guard let refreshingProvider = provider as? any RefreshingDaylightProviding else {
            return
        }

        refreshingProvider.onStatusChanged = { [weak self] in
            Task { @MainActor in
                self?.refresh()
            }
        }
        refreshingProvider.start()
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
            let contentSize = preferredPopoverContentSize()
            popover.contentSize = contentSize
            popover.contentViewController = makePopoverController(for: status, isPinned: false, contentSize: contentSize)
        }

        if let pinnedWindow, pinnedWindow.isVisible {
            pinnedWindow.contentViewController = makePinnedWindowController(for: status)
        }

        if let expandedMapWindow, expandedMapWindow.isVisible {
            expandedMapWindow.contentViewController = makeExpandedMapWindowController(for: status)
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
        let contentSize = preferredPopoverContentSize()
        popover.contentSize = contentSize
        popover.contentViewController = makePopoverController(for: status, isPinned: false, contentSize: contentSize)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    func showPinnedWindow() {
        let status = provider.status(at: .now)

        if pinnedWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 380, height: 540),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = "SunStatus"
            window.level = .floating
            window.isReleasedWhenClosed = false
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.delegate = self
            window.center()
            pinnedWindow = window
        }

        pinnedWindow?.contentViewController = makePinnedWindowController(for: status)
        pinnedWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func closePinnedWindow() {
        pinnedWindow?.close()
    }

    func windowWillClose(_ notification: Notification) {
        guard notification.object as? NSWindow === pinnedWindow else {
            return
        }
    }

    private func makePopoverController(
        for status: DaylightStatus,
        isPinned: Bool,
        contentSize: NSSize? = nil
    ) -> NSViewController {
        let contentSize = contentSize ?? preferredPopoverContentSize()
        let view = SunStatusPopoverView(
            status: status,
            isPinned: isPinned,
            contentHeight: contentSize.height,
            onOpenSettings: { [weak self] in
                self?.popover.performClose(nil)
                (NSApp.delegate as? AppDelegate)?.showSettingsWindow()
            },
            onOpenWindow: { [weak self] in
                self?.popover.performClose(nil)
                self?.showPinnedWindow()
            },
            onExpandMap: { [weak self] in
                self?.showExpandedMapWindow()
            },
            onClosePinned: { [weak self] in
                self?.closePinnedWindow()
            },
            onQuit: {
                NSApp.terminate(nil)
            }
        )

        let controller = NSHostingController(rootView: view)
        controller.preferredContentSize = contentSize
        return controller
    }

    private func preferredPopoverContentSize() -> NSSize {
        let screen = statusItem.button?.window?.screen ?? NSScreen.main
        let availableHeight = screen?.visibleFrame.height ?? 700
        let height = min(640, max(560, availableHeight - 10))
        return NSSize(width: 380, height: height)
    }

    private func makePinnedWindowController(for status: DaylightStatus) -> NSViewController {
        let view = PinnedSunStatusWindowView(
            status: status,
            onExpandMap: { [weak self] in
                self?.showExpandedMapWindow()
            },
            onClose: { [weak self] in
                self?.closePinnedWindow()
            }
        )

        let controller = NSHostingController(rootView: view)
        controller.preferredContentSize = NSSize(width: 380, height: 520)
        return controller
    }

    func showExpandedMapWindow() {
        let status = provider.status(at: .now)

        if expandedMapWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 980, height: 820),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "SunStatus Map"
            window.isReleasedWhenClosed = false
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.minSize = NSSize(width: 760, height: 700)
            window.delegate = self
            window.center()
            expandedMapWindow = window
        }

        expandedMapWindow?.contentViewController = makeExpandedMapWindowController(for: status)
        expandedMapWindow?.makeKeyAndOrderFront(nil)
        expandedMapWindow?.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makeExpandedMapWindowController(for status: DaylightStatus) -> NSViewController {
        let controller = NSHostingController(rootView: ExpandedSunMapWindowView(status: status))
        controller.preferredContentSize = NSSize(width: 980, height: 820)
        return controller
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
