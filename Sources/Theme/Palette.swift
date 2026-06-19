import SwiftUI

extension Color {
    /// Build a color from a packed `0xRRGGBB` literal.
    init(rgb: UInt32) {
        self.init(
            .sRGB,
            red: Double((rgb >> 16) & 0xFF) / 255,
            green: Double((rgb >> 8) & 0xFF) / 255,
            blue: Double(rgb & 0xFF) / 255,
            opacity: 1
        )
    }

    /// A color that resolves differently in light vs. dark appearance.
    init(light: Color, dark: Color) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(isDark ? dark : light)
        })
    }
}

/// Mirrorball's semantic colors. Chrome leans on system materials/semantic colors
/// so the app inherits native light/dark behavior; the status hues use Apple's
/// exact system colors so "green = up" reads instantly and correctly in both modes.
enum Palette {
    // Status — Apple system colors (brighter variants in dark mode, matching AppKit).
    static let statusUp = Color(light: Color(rgb: 0x34C759), dark: Color(rgb: 0x30D158))
    static let statusWarn = Color(light: Color(rgb: 0xFF9F0A), dark: Color(rgb: 0xFF9F0A))
    static let statusError = Color(light: Color(rgb: 0xFF3B30), dark: Color(rgb: 0xFF453A))
    static let statusOff = Color(light: Color(rgb: 0xC4C4C9), dark: Color(rgb: 0x5A5A5E))

    /// Resolve the dot/label color for a status.
    static func color(for status: ForwardStatus) -> Color {
        switch status {
        case .off: statusOff
        case .starting: statusWarn
        case .up: statusUp
        case .reconnecting: statusWarn
        case .error: statusError
        }
    }

    /// Tint for a kind badge.
    static func tint(for kind: ForwardKind) -> Color {
        switch kind {
        case .local: .accentColor
        case .remote: statusWarn
        case .dynamic: statusUp
        }
    }
}
