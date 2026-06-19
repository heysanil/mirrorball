import Foundation

/// Process-wide registry of live `ssh` children, so they can be torn down
/// synchronously when the app quits. Without this, quitting Mirrorball would
/// leak its tunnels as orphaned processes reparented to launchd.
///
/// Lock-protected (not an actor) precisely because `terminateAll()` must run
/// synchronously from `applicationWillTerminate`, which cannot await.
final class ChildProcessRegistry: @unchecked Sendable {
    static let shared = ChildProcessRegistry()

    private let lock = NSLock()
    private var table: [ObjectIdentifier: Process] = [:]

    func register(_ process: Process) {
        lock.withLock { table[ObjectIdentifier(process)] = process }
    }

    func unregister(_ process: Process) {
        lock.withLock { _ = table.removeValue(forKey: ObjectIdentifier(process)) }
    }

    /// Terminate every live child. Called on app teardown.
    func terminateAll() {
        let live = lock.withLock { Array(table.values) }
        for process in live where process.isRunning {
            process.terminate()
        }
        lock.withLock { table.removeAll() }
    }
}
