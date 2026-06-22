import SwiftUI

/// One forward in the management window: status, name, kind, address mapping,
/// and the on/off switch. Edit/Delete live in the context menu, and a
/// double-click opens the editor — both native Mac affordances.
struct ForwardRow: View {
    @Environment(AppModel.self) private var model
    let entry: ForwardEntry
    var onEdit: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: Metrics.rowSpacing) {
            StatusDot(status: entry.status)
                .accessibilityIdentifier(A11y.statusDot(entry.id.uuidString))

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(entry.forward.name)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    KindBadge(kind: entry.forward.kind)
                }

                HStack(spacing: 6) {
                    // The SSH host the tunnel runs over. Lower layout priority than
                    // the chips: when space is tight this truncates, the ports don't.
                    Text(entry.forward.target)
                        .font(.monoCaption())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    // One pill per port mapping. Capped to keep the row a single,
                    // fixed-height line; the rest collapse into a trailing "+N".
                    HStack(spacing: 4) {
                        ForEach(visibleMappings) { mapping in
                            PortChip(mapping: mapping, kind: entry.forward.kind)
                        }
                        if overflowCount > 0 {
                            MoreChip(count: overflowCount)
                        }
                    }
                    .fixedSize()
                }

                StatusDetail(status: entry.status)
            }

            Spacer(minLength: 8)

            Toggle("", isOn: enabledBinding)
                .toggleStyle(.switch)
                .controlSize(.small)
                .labelsHidden()
                .accessibilityIdentifier(A11y.toggle(entry.id.uuidString))
                .accessibilityLabel("\(entry.forward.name) enabled")
        }
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: onEdit)
        .contextMenu {
            Button("Edit…", action: onEdit)
            Button("Delete", role: .destructive) { model.delete(entry) }
        }
        .accessibilityIdentifier(A11y.row(entry.id.uuidString))
        .accessibilityElement(children: .contain)
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { entry.forward.enabled },
            set: { _ in model.toggle(entry) }
        )
    }

    /// How many port chips render before the rest fold into a "+N" pill.
    private static let maxVisibleChips = 4

    private var visibleMappings: ArraySlice<PortMapping> {
        entry.forward.mappings.prefix(Self.maxVisibleChips)
    }

    private var overflowCount: Int {
        max(0, entry.forward.mappings.count - Self.maxVisibleChips)
    }
}

/// Trailing "+N" pill standing in for the mappings beyond the visible cap, so the
/// row stays one fixed-height line no matter how many ports a connection carries.
private struct MoreChip: View {
    let count: Int

    var body: some View {
        Text("+\(count)")
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: Metrics.badgeCorner))
            .fixedSize()
            .help(label)
            .accessibilityLabel(label)
    }

    private var label: String { "\(count) more port\(count == 1 ? "" : "s")" }
}
