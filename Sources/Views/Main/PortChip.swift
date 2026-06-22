import SwiftUI

/// A compact, tinted pill describing one `PortMapping` on a row — the row-scale
/// companion to `KindBadge`. It shows the bind port (and the label, when set) in
/// a monospaced face; the full `host:port` spec lives in the hover tooltip so the
/// pill stays short even when a connection carries many mappings.
struct PortChip: View {
    let mapping: PortMapping
    /// The parent forward's kind — drives the tint and the tooltip spec.
    let kind: ForwardKind

    var body: some View {
        let tint = Palette.tint(for: kind)
        Text(text)
            // Slightly smaller and lighter than `KindBadge` so the kind still
            // reads as the louder label and a run of chips stays calm.
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(tint)
            .lineLimit(1)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: Metrics.badgeCorner))
            .fixedSize()
            .help(mapping.specDescription(for: kind))
            .accessibilityLabel(mapping.specDescription(for: kind))
    }

    /// `"<label> :<port>"` when labelled, otherwise a bare `":<port>"`.
    private var text: String {
        let label = mapping.label.trimmingCharacters(in: .whitespaces)
        return label.isEmpty ? ":\(mapping.listenPort)" : "\(label) :\(mapping.listenPort)"
    }
}
