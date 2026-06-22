import Foundation
@testable import Mirrorball

/// Writes an executable fake-`ssh` script whose body you control, returning its
/// URL. Lets integration tests drive the supervisor through up / drop / fail /
/// reconnect scenarios deterministically, with no real network or SSH.
@discardableResult
func makeFakeSSH(body: String) throws -> URL {
    let dir = FileManager.default.temporaryDirectory
        .appendingPathComponent("mb-fakessh-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    let url = dir.appendingPathComponent("ssh", isDirectory: false)
    let script = "#!/bin/bash\n\(body)\n"
    try script.write(to: url, atomically: true, encoding: .utf8)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    return url
}

/// Common fake-ssh behaviors.
enum FakeSSH {
    /// Connects and stays up until killed.
    static let staysUp = "exec sleep 100"
    /// Fails immediately with a recognizable stderr line (e.g. port in use).
    static let failsImmediately = #"echo "bind: Address already in use" >&2; exit 1"#
    /// Comes up, then drops after ~2s (long enough to pass the 1.5s grace window).
    static let dropsAfterComingUp = "sleep 2; exit 0"
}

/// Thread-safe sink for status updates streamed off the supervisor actor.
final class StatusCollector: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [ForwardStatus] = []

    var snapshot: [ForwardStatus] { lock.withLock { items } }

    func append(_ status: ForwardStatus) { lock.withLock { items.append(status) } }

    var sawUp: Bool { snapshot.contains(.up) }
    var sawReconnecting: Bool { snapshot.contains(.reconnecting) }
    var startingCount: Int { snapshot.filter { $0 == .starting }.count }
    var lastError: String? { snapshot.compactMap(\.errorMessage).last }
    var isOff: Bool { snapshot.last == .off }
}

/// Begin draining a status stream into a collector on a detached task.
func collectStatuses(from stream: AsyncStream<ForwardStatus>) -> StatusCollector {
    let collector = StatusCollector()
    Task.detached {
        for await status in stream {
            collector.append(status)
        }
    }
    return collector
}

/// Poll `predicate` until true or `timeout` elapses. Returns the final value.
@discardableResult
func poll(timeout: Duration, _ predicate: @Sendable () -> Bool) async -> Bool {
    let deadline = ContinuousClock.now.advanced(by: timeout)
    while ContinuousClock.now < deadline {
        if predicate() { return true }
        try? await Task.sleep(for: .milliseconds(50))
    }
    return predicate()
}

/// A minimal forward whose ssh args are irrelevant (the fake ignores them).
func sampleForward() -> Forward {
    Forward(name: "test", kind: .local, target: "host", listenPort: 5555, remoteHost: "localhost", remotePort: 5555)
}
