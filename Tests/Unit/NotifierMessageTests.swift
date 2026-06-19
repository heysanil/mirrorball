import Testing
@testable import MirrorballSwift

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
