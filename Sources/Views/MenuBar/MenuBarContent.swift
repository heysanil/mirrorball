import SwiftUI

/// The popover shown from the menu bar: a compact, scannable list of forwards
/// with quick toggles, plus actions to open the full window or quit.
struct MenuBarContent: View {
    @Environment(AppModel.self) private var model
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider().padding(.vertical, 4)

            if model.entries.isEmpty {
                Text("No forwards yet")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 10)
            } else {
                ForEach(model.entries) { entry in
                    MenuBarRow(entry: entry)
                }
            }

            Divider().padding(.vertical, 4)

            footer
        }
        .padding(10)
        .frame(width: Metrics.menuBarWidth)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 1) {
                Text("Mirrorball")
                    .font(.headline)
                Text(statusSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                openManager()
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(.borderless)
            .help("Add a forward")
        }
    }

    private var footer: some View {
        VStack(spacing: 2) {
            MenuBarActionButton(title: "Open Mirrorball", shortcut: "Open the management window") {
                openManager()
            }
            .accessibilityIdentifier(A11y.menuBarOpen)

            SettingsLink {
                Text("Settings…")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 6)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            MenuBarActionButton(title: "Quit Mirrorball", shortcut: nil) {
                NSApplication.shared.terminate(nil)
            }
        }
    }

    private var statusSummary: String {
        if model.anyError { return "Needs attention" }
        if model.entries.isEmpty { return "SSH port forwards" }
        let up = model.activeCount
        return up == 0 ? "All off" : "\(up) connected"
    }

    private func openManager() {
        openWindow(id: "manager")
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}

/// A single forward in the menu bar popover: dot, name + mapping, quick toggle.
private struct MenuBarRow: View {
    @Environment(AppModel.self) private var model
    let entry: ForwardEntry

    var body: some View {
        HStack(spacing: 8) {
            StatusDot(status: entry.status, diameter: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.forward.name)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Text(entry.forward.mappingDescription)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 6)
            Toggle("", isOn: enabledBinding)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
                .accessibilityIdentifier(A11y.toggle(entry.id.uuidString))
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 4)
    }

    private var enabledBinding: Binding<Bool> {
        Binding(get: { entry.forward.enabled }, set: { _ in model.toggle(entry) })
    }
}

/// Borderless full-width menu-style button with a hover highlight.
private struct MenuBarActionButton: View {
    let title: String
    let shortcut: String?
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
                .padding(.horizontal, 6)
                .background(
                    RoundedRectangle(cornerRadius: 5)
                        .fill(hovering ? Color.primary.opacity(0.08) : .clear)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(shortcut ?? "")
    }
}
