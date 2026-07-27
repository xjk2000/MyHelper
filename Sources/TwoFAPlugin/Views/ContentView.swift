import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var store: AuthenticatorStore
    @State private var editorMode: AccountEditorMode?
    @State private var pendingDeletion: TOTPAccount?

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            VStack(spacing: 0) {
                QuickSecretCodeView()

                Divider()

                DataStorageView()

                Divider()

                if store.accounts.isEmpty {
                    emptyState
                } else {
                    accountsList
                }
            }
        }
        .sheet(item: $editorMode) { mode in
            AccountEditorSheet(mode: mode)
                .environmentObject(store)
        }
        .alert("删除账号？", isPresented: deletionBinding) {
            Button("取消", role: .cancel) {
                pendingDeletion = nil
            }
            Button("删除", role: .destructive) {
                if let pendingDeletion {
                    store.delete(pendingDeletion)
                }
                pendingDeletion = nil
            }
        } message: {
            if let pendingDeletion {
                Text("将从本地 JSON 文件中移除 \(pendingDeletion.displayName)。")
            }
        }
        .alert("错误", isPresented: errorBinding) {
            Button("好") {
                store.errorMessage = nil
            }
        } message: {
            Text(store.errorMessage ?? "")
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("2FA 验证器")
                    .font(.title2.weight(.semibold))
                Text("在 MyHelper 中管理 TOTP 验证码，复制按钮会写入当前代码。")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            }

            Spacer()

            Button {
                editorMode = .add
            } label: {
                Label("添加账号", systemImage: "plus")
            }
            .keyboardShortcut("n", modifiers: .command)
        }
        .padding(20)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "lock.shield")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text("还没有账号")
                .font(.title3.weight(.semibold))
            Text("添加 TOTP Secret 或粘贴 otpauth:// 链接后即可生成验证码。")
                .foregroundStyle(.secondary)
            Button {
                editorMode = .add
            } label: {
                Label("添加第一个账号", systemImage: "plus")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var accountsList: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            List {
                ForEach(store.accounts) { account in
                    AccountRow(
                        account: account,
                        date: timeline.date,
                        edit: { editorMode = .edit(account) },
                        delete: { pendingDeletion = account }
                    )
                    .environmentObject(store)
                    .padding(.vertical, 6)
                }
            }
            .listStyle(.inset)
        }
    }

    private var deletionBinding: Binding<Bool> {
        Binding(
            get: { pendingDeletion != nil },
            set: { if !$0 { pendingDeletion = nil } }
        )
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } }
        )
    }
}

private struct DataStorageView: View {
    @EnvironmentObject private var store: AuthenticatorStore

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "externaldrive")
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 3) {
                Text("数据存储")
                    .font(.headline)
                Text(store.storageURL.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }

            Spacer()

            Menu {
                Button {
                    revealStorageFile()
                } label: {
                    Label("显示文件", systemImage: "folder")
                }

                Button {
                    chooseExistingStorageFile()
                } label: {
                    Label("使用现有文件", systemImage: "doc.badge.gearshape")
                }

                Divider()

                Button {
                    chooseStorageLocation()
                } label: {
                    Label("另存为", systemImage: "square.and.arrow.down")
                }
            } label: {
                Label("数据文件", systemImage: "externaldrive")
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private func chooseExistingStorageFile() {
        let panel = NSOpenPanel()
        panel.title = "选择要直接使用的 accounts.json"
        panel.message = "选择后会立即读取该文件，并把后续账号改动保存回这个文件。"
        panel.prompt = "使用"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.json]
        panel.directoryURL = store.storageURL.deletingLastPathComponent()

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        guard confirmUsingExistingFile(url) else {
            return
        }

        store.useExistingStorageFile(url)
    }

    private func confirmUsingExistingFile(_ url: URL) -> Bool {
        do {
            let count = try store.accountCount(inStorageFile: url)
            let alert = NSAlert()
            alert.messageText = "使用这个账号文件？"
            alert.informativeText = "将切换到：\n\(url.path)\n\n已识别 \(count) 个账号。后续新增、编辑和删除都会保存回这个文件。"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "使用")
            alert.addButton(withTitle: "取消")
            return alert.runModal() == .alertFirstButtonReturn
        } catch {
            store.errorMessage = "无法读取该账号文件：\(error.localizedDescription)"
            return false
        }
    }

    private func chooseStorageLocation() {
        let panel = NSSavePanel()
        panel.title = "将当前账号另存为 JSON"
        panel.message = "这会把当前账号写入所选文件，并把后续保存路径切到该文件。"
        panel.nameFieldStringValue = store.storageURL.lastPathComponent.isEmpty ? "accounts.json" : store.storageURL.lastPathComponent
        panel.directoryURL = store.storageURL.deletingLastPathComponent()
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        store.changeStorageLocation(to: url)
    }

    private func revealStorageFile() {
        let url = store.storageURL
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            NSWorkspace.shared.open(url.deletingLastPathComponent())
        }
    }
}

private struct QuickSecretCodeView: View {
    @State private var secretInput = ""
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("临时密钥取码")
                        .font(.headline)
                    Text("粘贴 Base32 Secret 或 otpauth:// 链接，直接生成验证码，不保存账号。")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }

                Spacer()

                Button {
                    pasteSecret()
                } label: {
                    Label("粘贴", systemImage: "doc.on.clipboard")
                }

                Button {
                    secretInput = ""
                    message = nil
                } label: {
                    Label("清空", systemImage: "xmark.circle")
                }
            }

            HStack(spacing: 12) {
                TextField("输入密钥或 otpauth:// 链接", text: $secretInput)
                    .textFieldStyle(.roundedBorder)

                TimelineView(.periodic(from: .now, by: 1)) { timeline in
                    let account = temporaryAccount()
                    VStack(alignment: .trailing, spacing: 3) {
                        Text(account.map { TOTPGenerator.code(for: $0, at: timeline.date) ?? "------" } ?? "------")
                            .font(.system(size: 24, weight: .semibold, design: .monospaced))
                            .textSelection(.enabled)
                        Text(account.map { "剩余 \(TOTPGenerator.remainingSeconds(for: $0, at: timeline.date)) 秒" } ?? "等待密钥")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: 130, alignment: .trailing)

                    Button {
                        if let account, let code = TOTPGenerator.code(for: account, at: timeline.date) {
                            Clipboard.copy(code)
                            message = "验证码已复制"
                        }
                    } label: {
                        Label("复制", systemImage: "doc.on.doc")
                    }
                    .disabled(account == nil)
                }
            }

            if let message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private func pasteSecret() {
        guard let value = NSPasteboard.general.string(forType: .string), !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            message = "剪贴板里没有可粘贴的文本"
            return
        }

        secretInput = value
        message = "已从剪贴板粘贴"
    }

    private func temporaryAccount() -> TOTPAccount? {
        let value = secretInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }

        if value.lowercased().hasPrefix("otpauth://") {
            return try? AccountInputParser.account(
                issuer: "",
                name: "",
                secretOrURL: value,
                digits: 6,
                period: 30
            )
        }

        guard (try? TOTPGenerator.validate(secret: value)) != nil else {
            return nil
        }

        return TOTPAccount(issuer: "临时密钥", name: "Quick Code", secret: value)
    }
}

private struct AccountRow: View {
    @EnvironmentObject private var store: AuthenticatorStore

    let account: TOTPAccount
    let date: Date
    let edit: () -> Void
    let delete: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(account.displayName)
                        .font(.headline)
                        .lineLimit(2)
                    if store.isSelectedForMenuBar(account) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.blue)
                            .help("菜单栏概览显示")
                    }
                }
                Text("每 \(account.period) 秒刷新 - \(account.digits) 位")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
            .frame(minWidth: 220, alignment: .leading)

            Spacer()

            VStack(alignment: .trailing, spacing: 5) {
                Text(store.code(for: account, at: date))
                    .font(.system(size: 28, weight: .semibold, design: .monospaced))
                    .textSelection(.enabled)
                ProgressView(value: store.progress(for: account, at: date))
                    .frame(width: 140)
                Text("剩余 \(store.remainingSeconds(for: account, at: date)) 秒")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button {
                store.copyCode(for: account, at: date)
            } label: {
                Label("复制", systemImage: "doc.on.doc")
            }
            .buttonStyle(.borderedProminent)

            Menu {
                Button {
                    store.selectForMenuBar(account)
                } label: {
                    Label("设为概览显示", systemImage: "star")
                }
                Divider()
                Button("编辑", action: edit)
                Button("删除", role: .destructive, action: delete)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
        }
    }
}
