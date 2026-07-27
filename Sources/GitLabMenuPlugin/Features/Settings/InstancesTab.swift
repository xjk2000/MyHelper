import SwiftUI

struct InstancesTab: View {
    @Environment(SettingsStore.self) private var settings
    @State private var selected: UUID?
    @State private var editing: GitLabInstance?
    @State private var editingToken: String = ""
    @State private var isNew: Bool = false
    @State private var saveError: String?
    @State private var verifyState: VerifyState = .idle

    enum VerifyState: Equatable {
        case idle, verifying
        case ok(String)         // username
        case failed(String)
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 10) {
                List(settings.config.instances, selection: $selected) { inst in
                    VStack(alignment: .leading) {
                        Text(inst.name).font(.body)
                        Text(inst.baseURL.absoluteString)
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .tag(inst.id)
                    .listRowBackground(Color.clear)
                }
                .frame(minWidth: 180)
                .scrollContentBackground(.hidden)

                HStack {
                    Button {
                        startNew()
                    } label: {
                        Label("新增", systemImage: "plus")
                    }
                    Button {
                        deleteSelected()
                    } label: {
                        Label("删除", systemImage: "minus")
                    }
                        .disabled(selected == nil)
                    Spacer()
                }
            }
            .glassPanel(cornerRadius: 16, padding: EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))

            VStack(alignment: .leading, spacing: 10) {
                if let editing {
                    InstanceEditor(
                        instance: Binding(
                            get: { editing },
                            set: { self.editing = $0 }
                        ),
                        token: $editingToken,
                        verifyState: $verifyState,
                        onVerify: verify,
                        onSave: save,
                        onCancel: cancel
                    )
                } else {
                    Text("选择左侧实例或点 + 新增").foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                if let saveError { Text(saveError).foregroundStyle(.red).font(.caption) }
            }
            .padding(2)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .glassPanel(cornerRadius: 16)
        }
        .padding(8)
        .frostedWindowBackground()
        .onChange(of: selected) { _, new in
            guard let new, let inst = settings.config.instances.first(where: { $0.id == new })
            else { editing = nil; saveError = nil; return }
            editing = inst
            editingToken = settings.token(for: new) ?? ""
            verifyState = .idle
            isNew = false
            saveError = nil
        }
    }

    private func startNew() {
        editing = GitLabInstance(
            id: UUID(),
            name: "新实例",
            baseURL: URL(string: "https://gitlab.example.com")!,
            defaultCloneRoot: FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("GitlabRepos"),
            cloneProtocol: .https
        )
        editingToken = ""
        verifyState = .idle
        isNew = true
        selected = nil
        saveError = nil
    }

    private func deleteSelected() {
        guard let id = selected else { return }
        do { try settings.removeInstance(id: id); editing = nil }
        catch { saveError = error.localizedDescription }
    }

    private func cancel() {
        editing = nil
        selected = nil
        isNew = false
    }

    private func verify() {
        guard let editing else { return }
        verifyState = .verifying
        Task {
            let client = GitLabClient(
                instance: editing,
                token: editingToken
            )
            do {
                let user = try await client.verifyToken()
                await MainActor.run {
                    verifyState = .ok(user.username)
                }
            } catch {
                await MainActor.run {
                    verifyState = .failed(error.localizedDescription)
                }
            }
        }
    }

    private func save() {
        guard let editing else { return }
        do {
            if isNew {
                try settings.addInstance(editing, token: editingToken)
            } else {
                try settings.updateInstance(editing, token: editingToken.isEmpty ? nil : editingToken)
            }
            saveError = nil
            isNew = false
            selected = editing.id
        } catch {
            saveError = error.localizedDescription
        }
    }
}
