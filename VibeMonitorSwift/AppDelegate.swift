import Cocoa
import SwiftUI
import Combine

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    var statusItem: NSStatusItem!
    var popover: NSPopover!
    var monitorState = MonitorState()
    private var statusBarTimer: Timer?
    private var hourglassPhase = 0

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // Create the status item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem.button {
            button.image = idleLogoImage()
            button.imagePosition = .imageLeading
            button.target = self
            button.action = #selector(togglePopover(_:))
            updateStatusBarText()
        }

        // Create the popover
        let popover = NSPopover()
        popover.contentSize = NSSize(width: 360, height: 520)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: PopoverView(state: monitorState)
        )
        self.popover = popover

        // Status bar update callback — called from MonitorState on every state change
        monitorState.onStatusBarUpdate = { [weak self] in
            self?.updateStatusBarText()
        }

        // 0.5s timer for elapsed time updates during active turns
        statusBarTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            Task { @MainActor in
                if self.monitorState.activeTurn != nil {
                    self.updateStatusBarText()
                }
            }
        }

        // Connect to backend
        Task { @MainActor in
            monitorState.connect()
        }
    }

    // MARK: - Dynamic Status Bar Text (5 states)

    private func updateStatusBarText() {
        guard let button = statusItem.button else { return }

        let state = monitorState.statusBarState
        let todayTotal = formatTimeCompact(monitorState.totalTime)

        switch state {
        case .disconnected:
            button.image = tintedSFImage("exclamationmark.triangle.fill", color: .systemRed)
            button.attributedTitle = styledText(" offline", color: .secondaryLabelColor)

        case .noData:
            button.image = idleLogoImage()
            button.attributedTitle = styledText(" ready", color: .tertiaryLabelColor)

        case .idle:
            button.image = idleLogoImage()
            button.attributedTitle = styledText(" \(todayTotal)", color: .labelColor)

        case .activeThinking(_, let elapsed):
            hourglassPhase = (hourglassPhase + 1) % 3
            button.image = hourglassImage()
            let e = formatTimeCompact(elapsed)
            button.attributedTitle = styledText(" \(e)/\(todayTotal)", color: NSColor(hex: "#a78bfa"))

        case .activeTool(_, let elapsed, let tool):
            hourglassPhase = (hourglassPhase + 1) % 3
            button.image = hourglassImage()
            let e = formatTimeCompact(elapsed)
            let t = String(tool.prefix(10))
            button.attributedTitle = styledText(" \(e)/\(todayTotal) \(t)", color: NSColor(hex: "#fbbf24"))
        }
    }

    private func styledText(_ text: String, color: NSColor) -> NSAttributedString {
        NSAttributedString(string: text, attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: color
        ])
    }

    // MARK: - Icon Helpers

    /// Animated hourglass icon — cycles through 3 SF Symbol variants on each tick
    private func hourglassImage() -> NSImage {
        let names = [
            "hourglass.tophalf.filled",
            "hourglass",
            "hourglass.bottomhalf.filled"
        ]
        let name = names[hourglassPhase % names.count]
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "Active turn")!
        let config = NSImage.SymbolConfiguration(paletteColors: [NSColor(hex: "#a78bfa")])
        return image.withSymbolConfiguration(config) ?? image
    }

    /// Idle logo: tries to load custom "IdleLogo" from Assets, falls back to SF Symbol
    private func idleLogoImage() -> NSImage {
        // Try loading custom logo from asset catalog
        if let custom = NSImage(named: "IdleLogo") {
            custom.isTemplate = true
            custom.size = NSSize(width: 16, height: 16)
            return custom
        }
        // Fallback: use a timer SF Symbol as template
        let image = NSImage(systemSymbolName: "timer", accessibilityDescription: "Vibe Monitor")!
        image.isTemplate = true
        return image
    }

    /// Helper to create a tinted SF Symbol image
    private func tintedSFImage(_ name: String, color: NSColor) -> NSImage {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "Vibe Monitor")!
        let config = NSImage.SymbolConfiguration(paletteColors: [color])
        return image.withSymbolConfiguration(config) ?? image
    }

    // MARK: - Popover

    @objc func togglePopover(_ sender: AnyObject?) {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        statusBarTimer?.invalidate()
        monitorState.disconnect()
    }
}

// MARK: - NSColor hex

extension NSColor {
    convenience init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var rgbValue: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&rgbValue)
        self.init(
            red: CGFloat((rgbValue & 0xFF0000) >> 16) / 255.0,
            green: CGFloat((rgbValue & 0x00FF00) >> 8) / 255.0,
            blue: CGFloat(rgbValue & 0x0000FF) / 255.0,
            alpha: 1.0
        )
    }
}

private func formatTimeCompact(_ seconds: Double) -> String {
    if seconds < 60 { return "\(Int(seconds))s" }
    let m = Int(seconds) / 60
    if m < 60 { return "\(m)m" }
    let h = m / 60
    let rm = m % 60
    return "\(h)h\(rm)m"
}
