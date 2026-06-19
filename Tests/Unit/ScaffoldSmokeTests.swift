import Testing
@testable import MirrorballSwift

@Suite("Scaffold smoke")
struct ScaffoldSmokeTests {
    @Test("Test bundle links against the app target")
    func bundleLinks() {
        // Placeholder proving the unit-test target builds and links the app.
        // Replaced by real model/argv tests as the core lands.
        #expect(Bool(true))
    }
}
