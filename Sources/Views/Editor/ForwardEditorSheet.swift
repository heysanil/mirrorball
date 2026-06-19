import SwiftUI

/// Add/edit sheet. Native grouped `Form`, segmented kind picker, and a host field
/// with a `~/.ssh/config` suggestions menu. Validation keeps the sheet open and
/// shows the error inline — saving is the only thing that dismisses it.
struct ForwardEditorSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    let target: EditorTarget
    @State private var draft: DraftForward
    @State private var validationError: String?

    init(target: EditorTarget) {
        self.target = target
        switch target {
        case .new:
            _draft = State(initialValue: DraftForward())
        case .edit(let entry):
            _draft = State(initialValue: DraftForward(entry.forward))
        }
    }

    private var isEditing: Bool {
        if case .edit = target { return true }
        return false
    }

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
        .frame(width: 380)
        .animation(.easeInOut(duration: 0.15), value: validationError)
        .task { model.refreshHostAliases() }
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

    private func save() {
        switch draft.validate() {
        case .failure(let error):
            validationError = error.message
        case .success(let forward):
            switch target {
            case .new:
                model.add(forward)
            case .edit(let entry):
                model.update(entry, with: forward)
            }
            dismiss()
        }
    }
}
