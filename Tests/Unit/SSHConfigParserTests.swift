import Testing
@testable import Mirrorball

@Suite("SSH config parser")
struct SSHConfigParserTests {
    @Test("Extracts host aliases in order")
    func extractsAliases() {
        let config = """
        Host prod
            HostName prod.example.com
            User deploy

        Host staging
            HostName staging.example.com
        """
        #expect(SSHConfigParser.aliases(fromContents: config) == ["prod", "staging"])
    }

    @Test("Skips wildcard and pattern entries")
    func skipsWildcards() {
        let config = """
        Host *
            ForwardAgent yes

        Host prod
            HostName prod.example.com

        Host *.internal
            User admin

        Host db?
            HostName db.example.com
        """
        #expect(SSHConfigParser.aliases(fromContents: config) == ["prod"])
    }

    @Test("Handles multiple aliases on one Host line")
    func multipleAliasesPerLine() {
        let config = "Host web1 web2 web3\n    HostName example.com"
        #expect(SSHConfigParser.aliases(fromContents: config) == ["web1", "web2", "web3"])
    }

    @Test("Is case-insensitive on the Host keyword and skips comments")
    func caseInsensitiveAndComments() {
        let config = """
        # a comment
        HOST prod
            HostName prod.example.com
        # Host commented
        host staging
        """
        #expect(SSHConfigParser.aliases(fromContents: config) == ["prod", "staging"])
    }

    @Test("De-duplicates repeated aliases")
    func deduplicates() {
        let config = "Host prod\nHost prod\nHost staging"
        #expect(SSHConfigParser.aliases(fromContents: config) == ["prod", "staging"])
    }

    @Test("Skips negated patterns")
    func skipsNegation() {
        let config = "Host !prod *.example.com gateway"
        #expect(SSHConfigParser.aliases(fromContents: config) == ["gateway"])
    }

    @Test("Empty config yields no aliases")
    func emptyConfig() {
        #expect(SSHConfigParser.aliases(fromContents: "").isEmpty)
    }
}
