import SwiftUI

struct InstanceEditor: View {
    @Binding var instance: GitLabInstance
    @Binding var token: String
    @Binding var verifyState: InstancesTab.VerifyState
    let onVerify: () -> Void
    let onSave: () -> Void
    let onCancel: () -> Void

    var body: some View {
        Form {
            TextField("名称", text: $instance.name)
            TextField(
                "Base URL",
                text: Binding(
                    get: { instance.baseURL.absoluteString },
                    set: { instance.baseURL = URL(string: $0) ?? instance.baseURL }
                )
            )
            SecureField("Personal Access Token", text: $token)

            Picker("Clone 协议", selection: $instance.cloneProtocol) {
                ForEach(CloneProtocol.allCases) { p in
                    Text(p.displayName).tag(p)
                }
            }
            .pickerStyle(.segmented)

            TextField(
                "默认 Clone 根目录",
                text: Binding(
                    get: { instance.defaultCloneRoot.path },
                    set: { instance.defaultCloneRoot = URL(fileURLWithPath: $0) }
                )
            )
            HStack {
                Button("选择目录…") {
                    let panel = NSOpenPanel()
                    panel.canChooseDirectories = true
                    panel.canChooseFiles = false
                    panel.allowsMultipleSelection = false
                    if panel.runModal() == .OK, let url = panel.url {
                        instance.defaultCloneRoot = url
                    }
                }
                Spacer()
            }

            Divider()

            HStack(spacing: 8) {
                Button(action: onVerify) {
                    if case .verifying = verifyState {
                        ProgressView().controlSize(.small)
                    } else { Text("验证 PAT") }
                }
                .disabled(token.isEmpty)
                switch verifyState {
                case .idle:           EmptyView()
                case .verifying:      Text("验证中…").foregroundStyle(.secondary)
                case .ok(let u):      Text("✓ \(u)").foregroundStyle(.green)
                case .failed(let m):  Text("✗ \(m)").foregroundStyle(.red).lineLimit(2)
                }
            }

            HStack {
                Spacer()
                Button("取消", action: onCancel)
                Button("保存", action: onSave)
                    .keyboardShortcut(.defaultAction)
                    .disabled(instance.name.isEmpty || token.isEmpty)
            }
        }
        .padding(8)
        .scrollContentBackground(.hidden)
    }
}
