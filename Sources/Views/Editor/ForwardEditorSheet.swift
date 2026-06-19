import SwiftUI
import AppKit

/// Add/edit sheet. Native grouped `Form` with kind, connection, authentication,
/// and advanced sections. Validation keeps the sheet open and shows the error
/// inline — saving is the only thing that dismisses it. Stored secrets are never
/// read back into the form; we only signal that one exists.
struct ForwardEditorSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    let target: EditorTarget
    private let entryID: UUID?
    @State private var draft: DraftForward
    @State private var validationError: String?

    init(target: EditorTarget) {
        self.target = target
        switch target {
        case .new:
            _draft = State(initialValue: DraftForward())
            entryID = nil
        case .edit(let entry):
            _draft = State(initialValue: DraftForward(entry.forward))
            entryID = entry.id
        }
    }

    private var isEditing: Bool { entryID != nil }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    TextField("Name", text: $draft.name, prompt: Text("Prod database"))
                        .accessibilityIdentifier(A11y.Editor.name)

                    Picker("Type", selection: $draft.kind) {
                        ForEach(ForwardKind.allCases) { kind in
                            Text(kind.title).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier(A11y.Editor.kind)

                    Text(draft.kind.explanation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Connection") {
                    hostField
                    TextField(draft.listenPortLabel, text: $draft.listenPort, prompt: Text("5432"))
                        .accessibilityIdentifier(A11y.Editor.listenPort)
                }

                if draft.kind.usesRemoteEndpoint {
                    Section("Destination (from the server)") {
                        TextField("Host", text: $draft.remoteHost, prompt: Text("localhost"))
                            .accessibilityIdentifier(A11y.Editor.remoteHost)
                        TextField("Port", text: $draft.remotePort, prompt: Text("5432"))
                            .accessibilityIdentifier(A11y.Editor.remotePort)
                    }
                }

                authenticationSection
                advancedSection
            }
            .formStyle(.grouped)

            if let validationError {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .foregroundStyle(Palette.statusError)
                    Text(validationError)
                        .font(.callout)
                        .foregroundStyle(Palette.statusError)
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 6)
                .accessibilityIdentifier(A11y.Editor.error)
                .transition(.opacity)
            }

            Divider()

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .accessibilityIdentifier(A11y.Editor.cancel)
                Button(isEditing ? "Save" : "Add") { save() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier(A11y.Editor.save)
            }
            .padding(16)
        }
        .frame(width: 400)
        .animation(.easeInOut(duration: 0.15), value: validationError)
        .task {
            model.refreshHostAliases()
            if let entryID { draft.hasStoredSecret = model.hasSecret(for: entryID) }
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var authenticationSection: some View {
        Section("Authentication") {
            Picker("Method", selection: $draft.authMethod) {
                ForEach(SSHAuthMethod.allCases) { method in
                    Text(method.title).tag(method)
                }
            }
            .pickerStyle(.segmented)
            .accessibilityIdentifier(A11y.Editor.authMethod)

            switch draft.authMethod {
            case .agent:
                Text("Uses your SSH agent and ~/.ssh/config keys.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .key:
                HStack(spacing: 6) {
                    TextField("Private key", text: $draft.identityFile, prompt: Text("~/.ssh/id_ed25519"))
                        .font(.system(size: 12, design: .monospaced))
                        .accessibilityIdentifier(A11y.Editor.identityFile)
                    Button("Choose…") { chooseIdentityFile() }
                        .accessibilityIdentifier(A11y.Editor.chooseKey)
                }
                secretField(label: "Passphrase", required: false)
            case .password:
                secretField(label: "Password", required: true)
            }
        }
    }

    @ViewBuilder
    private var advancedSection: some View {
        Section {
            DisclosureGroup("Advanced") {
                TextField("SSH port", text: $draft.sshPort, prompt: Text("22"))
                    .accessibilityIdentifier(A11y.Editor.sshPort)
                TextField("Jump host", text: $draft.jumpHost, prompt: Text("user@bastion"))
                    .accessibilityIdentifier(A11y.Editor.jumpHost)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Extra options")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    TextEditor(text: $draft.extraOptions)
                        .font(.system(size: 12, design: .monospaced))
                        .frame(height: 56)
                        .accessibilityIdentifier(A11y.Editor.extraOptions)
                    Text("One ssh -o option per line, e.g. ServerAliveInterval=30")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    @ViewBuilder
    private func secretField(label: String, required: Bool) -> some View {
        let keepHint = draft.hasStoredSecret && !draft.clearSecret
        SecureField(
            label,
            text: $draft.secretInput,
            prompt: Text(keepHint ? "Leave blank to keep stored secret" : (required ? "Required" : "Optional"))
        )
        .accessibilityIdentifier(A11y.Editor.secret)

        if draft.hasStoredSecret {
            HStack(spacing: 6) {
                if draft.clearSecret {
                    Image(systemName: "trash")
                        .foregroundStyle(Palette.statusWarn)
                    Text("Stored secret will be removed")
                        .font(.caption)
                        .foregroundStyle(Palette.statusWarn)
                    Spacer()
                    Button("Undo") { draft.clearSecret = false }
                        .buttonStyle(.link)
                } else {
                    Image(systemName: "lock.fill")
                        .foregroundStyle(.secondary)
                    Text("Stored in Keychain")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Remove") {
                        draft.clearSecret = true
                        draft.secretInput = ""
                    }
                    .buttonStyle(.link)
                    .accessibilityIdentifier(A11y.Editor.removeSecret)
                }
            }
        }
    }

    @ViewBuilder
    private var hostField: some View {
        HStack(spacing: 6) {
            TextField("SSH host", text: $draft.target, prompt: Text("alias or user@host"))
                .accessibilityIdentifier(A11y.Editor.target)
            if !model.hostAliases.isEmpty {
                Menu {
                    ForEach(model.hostAliases, id: \.self) { alias in
                        Button(alias) { draft.target = alias }
                    }
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.caption)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Pick a host from ~/.ssh/config")
            }
        }
    }

    // MARK: - Actions

    private func chooseIdentityFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        panel.prompt = "Choose"
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".ssh", isDirectory: true)
        if panel.runModal() == .OK, let url = panel.url {
            draft.identityFile = url.path
        }
    }

    private func save() {
        switch draft.validate() {
        case .failure(let error):
            validationError = error.message
        case .success(let forward):
            switch target {
            case .new:
                model.add(forward, secret: draft.secretUpdate())
            case .edit(let entry):
                model.update(entry, with: forward, secret: draft.secretUpdate())
            }
            dismiss()
        }
    }
}
