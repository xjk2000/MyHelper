import AppKit
import SwiftUI

enum AccountEditorMode: Identifiable {
    case add
    case edit(TOTPAccount)

    var id: String {
        switch self {
        case .add:
            return "add"
        case .edit(let account):
            return account.id.uuidString
        }
    }
}

struct AccountEditorSheet: View {
    @EnvironmentObject private var store: AuthenticatorStore
    @Environment(\.dismiss) private var dismiss

    let mode: AccountEditorMode

    @State private var issuer = ""
    @State private var name = ""
    @State private var secretOrURL = ""
    @State private var digits = 6
    @State private var period = 30
    @State private var validationMessage: String?
    @State private var infoMessage: String?

    init(mode: AccountEditorMode) {
        self.mode = mode
        if case .edit(let account) = mode {
            _issuer = State(initialValue: account.issuer)
            _name = State(initialValue: account.name)
            _secretOrURL = State(initialValue: account.secret)
            _digits = State(initialValue: account.digits)
            _period = State(initialValue: account.period)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(title)
                .font(.title2.weight(.semibold))

            Form {
                TextField("Issuer，例如 GitHub", text: $issuer)
                TextField("账号名，例如 name@example.com", text: $name)
                TextField("Secret 或 otpauth:// 链接", text: $secretOrURL, axis: .vertical)
                    .lineLimit(2...4)
                Stepper("验证码位数：\(digits)", value: $digits, in: 6...8)
                Stepper("刷新周期：\(period) 秒", value: $period, in: 15...120, step: 5)
            }
            .formStyle(.grouped)

            HStack(spacing: 10) {
                Button {
                    pasteSecretOrURL()
                } label: {
                    Label("粘贴", systemImage: "doc.on.clipboard")
                }

                Button {
                    scanQRCodeImageFile()
                } label: {
                    Label("扫描二维码图片", systemImage: "qrcode.viewfinder")
                }

                Button {
                    scanQRCodeScreenSelection()
                } label: {
                    Label("框选屏幕二维码", systemImage: "crop")
                }

                Button {
                    scanQRCodeFromPasteboard()
                } label: {
                    Label("扫描剪贴板图片", systemImage: "photo.on.rectangle")
                }
            }

            if let infoMessage {
                Text(infoMessage)
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }

            if let validationMessage {
                Text(validationMessage)
                    .foregroundStyle(.red)
                    .font(.callout)
            }

            HStack {
                Spacer()
                Button("取消") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button(primaryActionTitle) {
                    save()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 520)
    }

    private var title: String {
        switch mode {
        case .add:
            return "添加账号"
        case .edit:
            return "编辑账号"
        }
    }

    private var primaryActionTitle: String {
        switch mode {
        case .add:
            return "添加"
        case .edit:
            return "保存"
        }
    }

    private func save() {
        do {
            validationMessage = nil
            infoMessage = nil
            let existingID: UUID?
            if case .edit(let account) = mode {
                existingID = account.id
            } else {
                existingID = nil
            }

            let account = try AccountInputParser.account(
                issuer: issuer,
                name: name,
                secretOrURL: secretOrURL,
                digits: digits,
                period: period,
                existingID: existingID
            )

            switch mode {
            case .add:
                store.add(account)
            case .edit:
                store.update(account)
            }

            dismiss()
        } catch {
            validationMessage = error.localizedDescription
        }
    }

    private func pasteSecretOrURL() {
        guard let value = NSPasteboard.general.string(forType: .string), !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            validationMessage = "剪贴板里没有可粘贴的文本"
            infoMessage = nil
            return
        }

        secretOrURL = value
        validationMessage = nil
        infoMessage = "已从剪贴板粘贴"
    }

    private func scanQRCodeImageFile() {
        do {
            guard let payload = try QRCodeImportService.scanImageFile() else { return }
            try applyImportedPayload(payload)
        } catch {
            validationMessage = error.localizedDescription
            infoMessage = nil
        }
    }

    private func scanQRCodeScreenSelection() {
        do {
            guard let payload = try QRCodeImportService.scanScreenSelection() else { return }
            try applyImportedPayload(payload)
        } catch {
            validationMessage = error.localizedDescription
            infoMessage = nil
        }
    }

    private func scanQRCodeFromPasteboard() {
        do {
            let payload = try QRCodeImportService.scanPasteboardImage()
            try applyImportedPayload(payload)
        } catch {
            validationMessage = error.localizedDescription
            infoMessage = nil
        }
    }

    private func applyImportedPayload(_ payload: String) throws {
        let trimmedPayload = payload.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedPayload.lowercased().hasPrefix("otpauth://") {
            let account = try AccountInputParser.account(
                issuer: "",
                name: "",
                secretOrURL: trimmedPayload,
                digits: digits,
                period: period
            )
            issuer = account.issuer
            name = account.name
            secretOrURL = account.secret
            digits = account.digits
            period = account.period
            validationMessage = nil
            infoMessage = "已识别二维码：\(account.displayName)"
            return
        }

        try TOTPGenerator.validate(secret: trimmedPayload)
        secretOrURL = trimmedPayload
        validationMessage = nil
        infoMessage = "已识别二维码中的 Secret"
    }
}
