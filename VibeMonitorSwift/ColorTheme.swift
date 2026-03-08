import SwiftUI

// MARK: - Color Theme (matches web frontend CSS)

extension Color {
    // 5 time-category colors (from script.js COLORS)
    static let vmThinking    = Color(hex: "#a78bfa")  // purple
    static let vmTool        = Color(hex: "#fbbf24")  // yellow
    static let vmOutput      = Color(hex: "#38bdf8")  // blue
    static let vmNetwork     = Color(hex: "#fb7185")  // pink
    static let vmUnaccounted = Color(hex: "#94a3b8")  // gray

    // Connection status
    static let vmConnected    = Color(hex: "#34d399")  // green
    static let vmDisconnected = Color(hex: "#fb7185")  // red

    // Card background
    static let vmCardBg = Color.primary.opacity(0.05)

    // Project colors (from script.js PROJECT_COLORS)
    static let vmProjectColors: [Color] = [
        Color(hex: "#818cf8"), Color(hex: "#34d399"),
        Color(hex: "#fb923c"), Color(hex: "#f472b6"),
        Color(hex: "#22d3ee"), Color(hex: "#a78bfa"),
        Color(hex: "#facc15"), Color(hex: "#fb7185"),
    ]
}

// MARK: - Color from hex

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var rgbValue: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&rgbValue)
        let r = Double((rgbValue & 0xFF0000) >> 16) / 255.0
        let g = Double((rgbValue & 0x00FF00) >> 8) / 255.0
        let b = Double(rgbValue & 0x0000FF) / 255.0
        self.init(red: r, green: g, blue: b)
    }
}

// MARK: - Tool Name Formatter (matches script.js shortToolName)

func shortToolName(_ name: String) -> String {
    if name.hasPrefix("mcp__") {
        let stripped = name.replacingOccurrences(of: "mcp__", with: "")
        let parts = stripped.components(separatedBy: "__")
        let server = parts[0]
            .replacingOccurrences(of: "Claude_in_Chrome", with: "Chrome")
            .replacingOccurrences(of: "Claude_Preview", with: "Preview")
        if parts.count > 1 {
            return "\(server):\(parts.dropFirst().joined(separator: "_"))"
        }
        return server
    }
    return name
}

// MARK: - Time Formatter

func formatTime(_ seconds: Double) -> String {
    if seconds < 60 {
        return String(format: "%.1fs", seconds)
    }
    let m = Int(seconds) / 60
    let s = Int(seconds) % 60
    if m < 60 {
        return "\(m)m \(s)s"
    }
    let h = m / 60
    let rm = m % 60
    return "\(h)h \(rm)m"
}

// MARK: - Date Formatter

func formatDateFull(_ dateStr: String) -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    guard let date = formatter.date(from: dateStr) else { return dateStr }

    let display = DateFormatter()
    display.dateFormat = "EEE, MMM d"
    return display.string(from: date)
}

// MARK: - Project Color Helper

func projectColor(for name: String, allNames: [String]) -> Color {
    guard let index = allNames.firstIndex(of: name) else { return .vmThinking }
    return Color.vmProjectColors[index % Color.vmProjectColors.count]
}
