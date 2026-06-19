import SwiftUI

/// Status-item glyph. Reflects aggregate state at a glance: an alert when any
/// forward has errored, a "filled/connected" look when any tunnel is up, and a
/// quiet dotted icon when idle. Menu bar renders it as a monochrome template,
/// so state is carried by the symbol shape rather than color.
struct MenuBarLabel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Image(systemName: symbol)
            .accessibilityLabel("Mirrorball — \(summary)")
    }

    private var symbol: String {
        if model.anyError {
            return "exclamationmark.triangle"
        }
        return model.anyUp
            ? "point.3.filled.connected.trianglepath.dotted"
            : "point.3.connected.trianglepath.dotted"
    }

    private var summary: String {
        if model.anyError { return "a forward needs attention" }
        if model.anyUp { return "\(model.activeCount) connected" }
        return "idle"
    }
}
