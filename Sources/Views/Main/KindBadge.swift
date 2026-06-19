import SwiftUI

/// Small uppercase pill identifying the forward kind (LOCAL / REMOTE / SOCKS).
struct KindBadge: View {
    let kind: ForwardKind

    var body: some View {
        let tint = Palette.tint(for: kind)
        Text(kind.badge)
            .font(.system(size: 10, weight: .semibold))
            .tracking(0.4)
            .foregroundStyle(tint)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(tint.opacity(0.15), in: RoundedRectangle(cornerRadius: Metrics.badgeCorner))
            .accessibilityLabel("\(kind.title) forward")
    }
}
