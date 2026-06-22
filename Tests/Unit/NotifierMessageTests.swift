import Foundation
import Testing
@testable import Mirrorball

@Suite("Notifier copy")
struct NotifierMessageTests {
    @Test("Drop from up announces a dropped connection")
    func dropAnnounced() {
        let message = Notifier.message(name: "Prod", from: .up, to: .reconnecting)
        #expect(message?.title == "Connection dropped")
        #expect(message?.body.contains("Prod") == true)
    }

    @Test("Recovery from reconnecting announces reconnection")
    func recoveryAnnounced() {
        let message = Notifier.message(name: "Prod", from: .reconnecting, to: .up)
        #expect(message?.title == "Reconnected")
    }

    @Test("Entering error announces a failure with detail")
    func errorAnnounced() {
        let message = Notifier.message(name: "Prod", from: .starting, to: .error("bind failed"))
        #expect(message?.title == "Forward failed")
        #expect(message?.body.contains("bind failed") == true)
    }

    @Test("Error to error churn stays quiet")
    func errorChurnSilent() {
        #expect(Notifier.message(name: "Prod", from: .error("a"), to: .error("b")) == nil)
    }

    @Test("First connect (off/starting to up) stays quiet")
    func firstConnectSilent() {
        #expect(Notifier.message(name: "Prod", from: .starting, to: .up) == nil)
        #expect(Notifier.message(name: "Prod", from: .off, to: .up) == nil)
    }

    @Test("Routine transitions produce no message")
    func routineSilent() {
        #expect(Notifier.message(name: "Prod", from: .off, to: .starting) == nil)
        #expect(Notifier.message(name: "Prod", from: .up, to: .off) == nil)
    }
}

/// Records every delivered notification so debounce behavior can be asserted
/// without touching the real notification center.
@MainActor
final class MessageRecorder {
    private(set) var messages: [Notifier.Message] = []
    func record(_ message: Notifier.Message) { messages.append(message) }
    var titles: [String] { messages.map(\.title) }
}

@Suite("Notifier debounce")
@MainActor
struct NotifierDebounceTests {
    private func makeNotifier(_ recorder: MessageRecorder) -> Notifier {
        // A tiny settle window so tests resolve in milliseconds, not the 5s default.
        Notifier(enabled: true, settleDelay: .milliseconds(60), deliver: recorder.record)
    }

    @Test("A drop that recovers within the settle window stays silent")
    func briefDropIsSilent() async {
        let recorder = MessageRecorder()
        let notifier = makeNotifier(recorder)
        let id = UUID()

        notifier.handleStatus(id: id, name: "Prod", status: .starting)
        notifier.handleStatus(id: id, name: "Prod", status: .up)            // established
        notifier.handleStatus(id: id, name: "Prod", status: .reconnecting)  // drops…
        notifier.handleStatus(id: id, name: "Prod", status: .up)            // …recovers right away

        try? await Task.sleep(for: .milliseconds(220))
        #expect(recorder.messages.isEmpty)
    }

    @Test("A drop that persists past the settle window announces, and its recovery announces")
    func sustainedDropAnnouncesAndRecovers() async {
        let recorder = MessageRecorder()
        let notifier = makeNotifier(recorder)
        let id = UUID()

        notifier.handleStatus(id: id, name: "Prod", status: .up)
        notifier.handleStatus(id: id, name: "Prod", status: .reconnecting)
        try? await Task.sleep(for: .milliseconds(220))            // outage outlasts the window
        #expect(recorder.titles == ["Connection dropped"])

        notifier.handleStatus(id: id, name: "Prod", status: .up)  // recovery is announced
        #expect(recorder.titles == ["Connection dropped", "Reconnected"])
    }

    @Test("A sustained error announces the failure with its detail")
    func sustainedErrorAnnounces() async {
        let recorder = MessageRecorder()
        let notifier = makeNotifier(recorder)
        let id = UUID()

        notifier.handleStatus(id: id, name: "Prod", status: .up)
        notifier.handleStatus(id: id, name: "Prod", status: .error("Permission denied"))
        try? await Task.sleep(for: .milliseconds(220))

        #expect(recorder.messages.count == 1)
        #expect(recorder.messages.first?.title == "Forward failed")
        #expect(recorder.messages.first?.body.contains("Permission denied") == true)
    }

    @Test("The initial connect never notifies, even if it lingers before coming up")
    func firstConnectIsSilent() async {
        let recorder = MessageRecorder()
        let notifier = makeNotifier(recorder)
        let id = UUID()

        notifier.handleStatus(id: id, name: "Prod", status: .starting)
        try? await Task.sleep(for: .milliseconds(220))            // lingers in starting past the window
        notifier.handleStatus(id: id, name: "Prod", status: .up)
        try? await Task.sleep(for: .milliseconds(220))

        #expect(recorder.messages.isEmpty)
    }

    @Test("Turning a forward off cancels a pending drop announcement")
    func offCancelsPendingOutage() async {
        let recorder = MessageRecorder()
        let notifier = makeNotifier(recorder)
        let id = UUID()

        notifier.handleStatus(id: id, name: "Prod", status: .up)
        notifier.handleStatus(id: id, name: "Prod", status: .reconnecting)
        notifier.forget(id: id)                                   // user toggles it off before the window elapses

        try? await Task.sleep(for: .milliseconds(220))
        #expect(recorder.messages.isEmpty)
    }
}
