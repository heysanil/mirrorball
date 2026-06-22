import SwiftUI
import AppKit

/// Add/edit sheet. The single, unified editor for a connection: it's simple by
/// default — a name, a host, and a list of port mappings — with all the power
/// (type, SSH port, jump host, per-port destination host, extra options) tucked
/// behind an "Advanced" disclosure. Native grouped `Form`; validation keeps the
/// sheet open and shows the error inline — saving is the only thing that
/// dismisses it. Stored secrets are never read back into the form; we only
/// signal that one exists.
struct ForwardEditorSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    let target: EditorTarget
    private let entryID: UUID?
    @State private var draft: DraftForward
    @State private var validationError: String?
    /// Drives the Advanced disclosure. Also reveals each port row's optional
    /// destination-host field, so non-localhost destinations stay reachable
    /// without a second sheet.
    @State private var showAdvanced = false

    init(target: EditorTarget) {
        self.target = target
        switch target {
        case .new:
            _draft = State(initialValue: DraftForward())
            entryID = nil
            _showAdvanced = State(initialValue: false)
        case .edit(let entry):
            _draft = State(initialValue: DraftForward(entry.forward))
            entryID = entry.id
            // Open Advanced when editing a forward that actually uses it, so its
            // type / jump host / per-port destination host aren't hidden behind a
            // "simple" view that silently omits configured values.
            _showAdvanced = State(initialValue: Self.usesAdvanced(entry.forward))
        }
    }

    private var isEditing: Bool { entryID != nil }

    /// Whether a forward exercises any surface that lives under the Advanced
    /// disclosure (a non-local type, a custom SSH port / jump host / extra options,
    /// or a destination host other than `localhost` on any mapping).
    private static func usesAdvanced(_ forward: Forward) -> Bool {
        forward.kind != .local
            || forward.sshPort != nil
            || (forward.jumpHost?.isEmpty == false)
            || !forward.extraOptions.isEmpty
            || forward.mappings.contains { $0.effectiveRemoteHost != "localhost" }
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                // Identity — the two things you always need: a name and a host.
                Section {
                    TextField("Name", text: $draft.name, prompt: Text("Prod database"))
                        .accessibilityIdentifier(A11y.Editor.name)
                    hostField
                }

                portsSection
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
        .frame(width: Metrics.windowWidth)
        .animation(.easeInOut(duration: 0.15), value: validationError)
        .task {
            model.refreshHostAliases()
            if let entryID { draft.hasStoredSecret = model.hasSecret(for: entryID) }
        }
    }

    // MARK: - Sections

    /// The list of port mappings carried over this one connection. Each row is a
    /// compact `[label] [listen] → [dest]` (just `[label] [listen]` for `.dynamic`);
    /// "Add port" appends another. With Advanced open, each row also reveals a
    /// destination-host field.
    @ViewBuilder
    private var portsSection: some View {
        Section("Ports") {
            ForEach($draft.mappings) { $mapping in
                // Recover this mapping's position for the indexed a11y identifiers
                // (keying off the stable id keeps it correct across add/remove).
                let index = draft.mappings.firstIndex { $0.id == mapping.id } ?? 0
                portRow(index: index, mapping: $mapping)
            }

            Button {
                draft.mappings.append(DraftPortMapping())
            } label: {
                Label("Add port", systemImage: "plus.circle")
            }
            .buttonStyle(.borderless)
            .accessibilityIdentifier(A11y.Editor.addPort)
        }
    }

    /// One port-mapping row. The compact line adapts to the connection's kind;
    /// when `showAdvanced` is on (and the kind has a remote endpoint) a second
    /// row exposes the destination host.
    @ViewBuilder
    private func portRow(index: Int, mapping: Binding<DraftPortMapping>) -> some View {
        let listenValue = mapping.wrappedValue.listenPort.trimmingCharacters(in: .whitespaces)

        HStack(spacing: 8) {
            // Optional human label, e.g. "frontend". Takes the slack in the row.
            TextField("Label", text: mapping.label, prompt: Text("label"))
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier(A11y.Editor.portLabel(index))

            // The bound port — local for -L/-D, server-side for -R.
            TextField(draft.listenPortLabel, text: mapping.listenPort, prompt: Text("5432"))
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .frame(width: 76)
                .accessibilityIdentifier(A11y.Editor.listenPort(index))

            if draft.kind.usesRemoteEndpoint {
                Image(systemName: "arrow.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                // Destination port; blank mirrors the listen port (smart default),
                // so the placeholder echoes it once one's been typed.
                TextField(
                    "Destination port",
                    text: mapping.remotePort,
                    prompt: Text(listenValue.isEmpty ? "= local" : listenValue)
                )
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .frame(width: 76)
                .accessibilityIdentifier(A11y.Editor.remotePort(index))
            }

            // Never allow zero rows — hide (but keep the slot) on the last one.
            Button {
                removeMapping(at: index)
            } label: {
                Image(systemName: "xmark.circle")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
            .help("Remove this port")
            .disabled(draft.mappings.count == 1)
            .opacity(draft.mappings.count == 1 ? 0 : 1)
            .accessibilityIdentifier(A11y.Editor.removePort(index))
        }

        // Advanced: a non-localhost destination host for this mapping.
        if showAdvanced && draft.kind.usesRemoteEndpoint {
            TextField("Destination host", text: mapping.remoteHost, prompt: Text("localhost"))
                .font(.system(size: 12, design: .monospaced))
                .accessibilityIdentifier(A11y.Editor.remoteHost(index))
        }
    }

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
            DisclosureGroup("Advanced", isExpanded: $showAdvanced) {
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

    /// Drop one port mapping, refusing to leave the connection with none.
    private func removeMapping(at index: Int) {
        guard draft.mappings.count > 1, draft.mappings.indices.contains(index) else { return }
        draft.mappings.remove(at: index)
    }

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
