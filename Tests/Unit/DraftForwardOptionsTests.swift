import Testing
@testable import MirrorballSwift

@Suite("Draft validation — SSH options & secrets")
struct DraftForwardOptionsTests {
    private func validBase() -> DraftForward {
        var d = DraftForward()
        d.name = "x"
        d.target = "host"
        d.listenPort = "5432"
        d.remoteHost = "db"
        d.remotePort = "5432"
        return d
    }

    @Test("Blank SSH port is allowed and yields nil")
    func blankSSHPort() throws {
        var d = validBase(); d.sshPort = ""
        let f = try d.validate().get()
        #expect(f.sshPort == nil)
    }

    @Test("Valid SSH port parses; garbage/out-of-range is rejected")
    func sshPortValidation() throws {
        var d = validBase(); d.sshPort = "2222"
        #expect(try d.validate().get().sshPort == 2222)

        d.sshPort = "0"
        #expect(throws: ValidationError.self) { try d.validate().get() }
        d.sshPort = "70000"
        #expect(throws: ValidationError.self) { try d.validate().get() }
        d.sshPort = "abc"
        #expect(throws: ValidationError.self) { try d.validate().get() }
    }

    @Test("Extra options accept Key=Value lines and reject lines without =")
    func extraOptionsValidation() throws {
        var d = validBase()
        d.extraOptions = "Compression=yes\n\n  ServerAliveInterval=30  "
        let f = try d.validate().get()
        #expect(f.extraOptions == ["Compression=yes", "ServerAliveInterval=30"])

        d.extraOptions = "Compression yes"
        #expect(throws: ValidationError.self) { try d.validate().get() }
    }

    @Test("Key auth requires an identity file")
    func keyRequiresIdentity() {
        var d = validBase(); d.authMethod = .key; d.identityFile = ""
        #expect(throws: ValidationError.self) { try d.validate().get() }
    }

    @Test("Password auth requires a secret unless one is stored")
    func passwordRequiresSecret() throws {
        var d = validBase(); d.authMethod = .password
        d.secretInput = ""; d.hasStoredSecret = false
        #expect(throws: ValidationError.self) { try d.validate().get() }

        d.secretInput = "hunter2"
        #expect(throws: Never.self) { try d.validate().get() }

        d.secretInput = ""; d.hasStoredSecret = true
        #expect(throws: Never.self) { try d.validate().get() }

        // Removing the stored secret with no replacement is invalid again.
        d.clearSecret = true
        #expect(throws: ValidationError.self) { try d.validate().get() }
    }

    @Test("secretUpdate reflects clear / set / unchanged")
    func secretUpdateLogic() {
        var d = validBase()
        #expect(d.secretUpdate() == .unchanged)
        d.secretInput = "pw"
        #expect(d.secretUpdate() == .set("pw"))
        d.clearSecret = true
        #expect(d.secretUpdate() == .clear)  // clear wins
    }

    @Test("A full key-auth draft carries every option through")
    func fullKeyDraft() throws {
        var d = validBase()
        d.authMethod = .key
        d.identityFile = "  ~/.ssh/id_ed25519  "
        d.sshPort = "2200"
        d.jumpHost = "  user@bastion  "
        d.extraOptions = "ServerAliveInterval=30"
        let f = try d.validate().get()
        #expect(f.authMethod == .key)
        #expect(f.identityFile == "~/.ssh/id_ed25519")
        #expect(f.sshPort == 2200)
        #expect(f.jumpHost == "user@bastion")
        #expect(f.extraOptions == ["ServerAliveInterval=30"])
    }

    @Test("Identity file is dropped when auth method isn't key")
    func identityDroppedForNonKey() throws {
        var d = validBase(); d.authMethod = .agent; d.identityFile = "~/.ssh/id_rsa"
        let f = try d.validate().get()
        #expect(f.identityFile == nil)
    }
}
