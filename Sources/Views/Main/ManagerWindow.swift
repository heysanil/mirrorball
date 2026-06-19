import SwiftUI

/// The full management window: a native list of forwards with a toolbar add
/// button, an empty state, and the editor presented as a sheet.
struct ManagerWindow: View {
    @Environment(AppModel.self) private var model
    @State private var editorTarget: EditorTarget?

    var body: some View {
        Group {
            if model.entries.isEmpty {
                EmptyStateView { editorTarget = .new }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                list
            }
        }
        .frame(minWidth: Metrics.windowWidth, minHeight: Metrics.windowMinHeight)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    editorTarget = .new
                } label: {
                    Label("Add Forward", systemImage: "plus")
                }
                .help("Add a new forward (⌘N)")
                .accessibilityIdentifier(A11y.addButton)
            }
        }
        .navigationTitle("Mirrorball")
        .navigationSubtitle(subtitle)
        .sheet(item: $editorTarget) { target in
            ForwardEditorSheet(target: target)
                .environment(model)
        }
        .onReceive(NotificationCenter.default.publisher(for: .mbNewForward)) { _ in
            editorTarget = .new
        }
    }

    /// Live status line shown next to the window title.
    private var subtitle: String {
        if model.entries.isEmpty { return "No forwards" }
        if model.anyError { return "Needs attention" }
        let up = model.activeCount
        let total = model.entries.count
        if up == 0 { return "\(total) forward\(total == 1 ? "" : "s")" }
        return "\(up) of \(total) connected"
    }

    private var list: some View {
        List {
            ForEach(model.entries) { entry in
                ForwardRow(entry: entry) { editorTarget = .edit(entry) }
                    .listRowInsets(EdgeInsets(top: 2, leading: 6, bottom: 2, trailing: 6))
            }
            .onDelete { model.delete(at: $0) }
        }
        .listStyle(.inset)
        .accessibilityIdentifier(A11y.forwardList)
    }
}
