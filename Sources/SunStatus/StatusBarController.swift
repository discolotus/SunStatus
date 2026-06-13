import AppKit
import CoreLocation
import SwiftUI
#if canImport(SunStatusCore)
import SunStatusCore
#endif

@MainActor
final class StatusBarController: NSObject, NSPopoverDelegate, NSWindowDelegate {
    private let provider: DaylightProviding
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private var pinnedWindow: NSWindow?
    private var expandedMapWindow: NSWindow?
    private var timer: Timer?
    private let selectedLocationWeatherService = WeatherService()
    private var selectedLocationCoordinate: Coordinate?
    private var selectedLocationWeatherCoordinate: Coordinate?
    private var selectedLocationWeather: WeatherSnapshot?
    private var selectedLocationWeatherTask: Task<Void, Never>?

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
        let status = currentStatus()

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

        let status = currentStatus()
        let contentSize = preferredPopoverContentSize()
        popover.contentSize = contentSize
        popover.contentViewController = makePopoverController(for: status, isPinned: false, contentSize: contentSize)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    func showPinnedWindow() {
        let status = currentStatus()

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
            configureCenteredTitle(for: window)
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
            onRecenterToUserLocation: { [weak self] coordinate in
                self?.selectCurrentLocation(coordinate)
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
            onRecenterToUserLocation: { [weak self] coordinate in
                self?.selectCurrentLocation(coordinate)
            }
        )

        let controller = NSHostingController(rootView: view)
        controller.preferredContentSize = NSSize(width: 380, height: 520)
        return controller
    }

    func showExpandedMapWindow() {
        let status = currentStatus()

        if expandedMapWindow == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 980, height: 820),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "SunStatus"
            window.isReleasedWhenClosed = false
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.minSize = NSSize(width: 760, height: 700)
            window.delegate = self
            configureCenteredTitle(for: window)
            window.center()
            expandedMapWindow = window
        }

        expandedMapWindow?.contentViewController = makeExpandedMapWindowController(for: status)
        expandedMapWindow?.makeKeyAndOrderFront(nil)
        expandedMapWindow?.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makeExpandedMapWindowController(for status: DaylightStatus) -> NSViewController {
        let controller = NSHostingController(
            rootView: ExpandedSunMapWindowView(
                status: status,
                onRecenterToUserLocation: { [weak self] coordinate in
                    self?.selectCurrentLocation(coordinate)
                }
            )
        )
        controller.preferredContentSize = NSSize(width: 980, height: 820)
        return controller
    }

    private func currentStatus(at date: Date = .now) -> DaylightStatus {
        guard let selectedLocationCoordinate else {
            return provider.status(at: date)
        }

        return SolarDaylightProvider(
            locationName: "Current Location",
            coordinate: selectedLocationCoordinate,
            timezone: .current,
            weather: selectedLocationWeather
        )
        .status(at: date)
    }

    private func selectCurrentLocation(_ coordinate: Coordinate) {
        let didMove = selectedLocationCoordinate.map { distance(from: $0, to: coordinate) > 5 } ?? true

        if didMove {
            selectedLocationCoordinate = coordinate

            if shouldClearSelectedLocationWeather(for: coordinate) {
                selectedLocationWeather = nil
            }

            refresh()
        }

        refreshSelectedLocationWeather(for: coordinate)
    }

    private func shouldClearSelectedLocationWeather(for coordinate: Coordinate) -> Bool {
        guard let selectedLocationWeatherCoordinate else {
            return selectedLocationWeather != nil
        }

        return distance(from: selectedLocationWeatherCoordinate, to: coordinate) > 250
    }

    private func refreshSelectedLocationWeather(for coordinate: Coordinate) {
        let needsFreshCoordinate = selectedLocationWeatherCoordinate
            .map { distance(from: $0, to: coordinate) > 250 } ?? true

        guard needsFreshCoordinate || selectedLocationWeather == nil else {
            return
        }

        selectedLocationWeatherCoordinate = coordinate
        selectedLocationWeatherTask?.cancel()

        let weatherService = selectedLocationWeatherService
        selectedLocationWeatherTask = Task { [weak self, weatherService] in
            let snapshot = await weatherService.weather(for: coordinate)

            guard !Task.isCancelled else {
                return
            }

            await MainActor.run { [weak self] in
                guard let self,
                      let selectedLocationCoordinate = self.selectedLocationCoordinate,
                      self.distance(from: selectedLocationCoordinate, to: coordinate) <= 250 else {
                    return
                }

                self.selectedLocationWeather = snapshot
                self.refresh()
            }
        }
    }

    private func distance(from lhs: Coordinate, to rhs: Coordinate) -> CLLocationDistance {
        CLLocation(latitude: lhs.latitude, longitude: lhs.longitude)
            .distance(from: CLLocation(latitude: rhs.latitude, longitude: rhs.longitude))
    }

    private func configureCenteredTitle(for window: NSWindow) {
        window.titleVisibility = .hidden

        let titleLabel = NSTextField(labelWithString: "SunStatus")
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.alignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false

        let titlebarView = window.standardWindowButton(.closeButton)?.superview
            ?? window.contentView?.superview
        guard let titlebarView else {
            return
        }

        titlebarView.addSubview(titleLabel)
        if let closeButton = window.standardWindowButton(.closeButton) {
            NSLayoutConstraint.activate([
                titleLabel.centerXAnchor.constraint(equalTo: titlebarView.centerXAnchor),
                titleLabel.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor)
            ])
        } else {
            NSLayoutConstraint.activate([
                titleLabel.centerXAnchor.constraint(equalTo: titlebarView.centerXAnchor),
                titleLabel.topAnchor.constraint(equalTo: titlebarView.topAnchor, constant: 10)
            ])
        }
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
