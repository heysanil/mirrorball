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
                    Text(entry.forward.target)
                        .font(.monoCaption())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text(entry.forward.mappingDescription)
                        .font(.monoCaption())
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
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
}
