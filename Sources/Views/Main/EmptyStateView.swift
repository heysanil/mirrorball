import SwiftUI

/// Friendly first-run state shown when there are no forwards yet.
struct EmptyStateView: View {
    var onAdd: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "point.3.connected.trianglepath.dotted")
                .font(.system(size: 38, weight: .light))
                .foregroundStyle(.tertiary)
            VStack(spacing: 4) {
                Text("No forwards yet")
                    .font(.headline)
                Text("Add an SSH port forward to bring a remote service to this Mac.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 280)
            }
            Button(action: onAdd) {
                Label("Add Forward", systemImage: "plus")
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
        }
        .padding(40)
        .accessibilityIdentifier(A11y.emptyState)
    }
}
