import SwiftUI

/// Layout constants tuned for a compact, native-feeling utility window.
enum Metrics {
    static let cardCorner: CGFloat = 10
    static let badgeCorner: CGFloat = 5

    static let windowWidth: CGFloat = 460
    static let windowMinHeight: CGFloat = 420
    static let menuBarWidth: CGFloat = 320

    /// Top inset reserving room for the traffic lights under a hidden title bar.
    static let trafficLightInset: CGFloat = 30

    static let rowSpacing: CGFloat = 10
    static let contentPadding: CGFloat = 16
}

extension Font {
    /// Monospaced face for technical text (targets, ports, addresses).
    static func monoCaption() -> Font { .system(size: 12, design: .monospaced) }
}
