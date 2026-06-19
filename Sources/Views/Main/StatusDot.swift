import SwiftUI

/// A colored status dot that gains a soft glow when the tunnel is up. Used in
/// rows and the menu bar.
struct StatusDot: View {
    let status: ForwardStatus
    var diameter: CGFloat = 9

    var body: some View {
        let color = Palette.color(for: status)
        Circle()
            .fill(color)
            .frame(width: diameter, height: diameter)
            .shadow(color: status == .up ? color.opacity(0.8) : .clear, radius: status == .up ? 3.5 : 0)
            .animation(.easeInOut(duration: 0.25), value: status)
            .accessibilityLabel(status.shortLabel)
    }
}

/// Inline progress/error detail shown beneath a row while connecting,
/// reconnecting, or after a failure.
struct StatusDetail: View {
    let status: ForwardStatus

    var body: some View {
        switch status {
        case .starting:
            label("Connecting…", color: .secondary, spinning: true)
        case .reconnecting:
            label("Reconnecting…", color: Palette.statusWarn, spinning: true)
        case .error(let message):
            HStack(spacing: 5) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Palette.statusError)
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(Palette.statusError)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(message)
            }
        case .off, .up:
            EmptyView()
        }
    }

    private func label(_ text: String, color: Color, spinning: Bool) -> some View {
        HStack(spacing: 5) {
            if spinning {
                ProgressView()
                    .controlSize(.mini)
                    .scaleEffect(0.7)
                    .frame(width: 10, height: 10)
            }
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(color)
        }
    }
}
