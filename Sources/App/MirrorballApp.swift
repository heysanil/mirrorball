import SwiftUI

@main
struct MirrorballApp: App {
    var body: some Scene {
        WindowGroup("Mirrorball", id: "manager") {
            Text("Mirrorball")
                .frame(minWidth: 460, minHeight: 580)
        }

        MenuBarExtra("Mirrorball", systemImage: "circle.dotted") {
            Text("Mirrorball")
        }
        .menuBarExtraStyle(.window)
    }
}
