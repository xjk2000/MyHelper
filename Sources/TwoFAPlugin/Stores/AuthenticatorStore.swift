import AppKit
import Foundation

final class AuthenticatorStore: ObservableObject {
    @Published private(set) var accounts: [TOTPAccount] = []
    @Published private(set) var storageURL: URL
    @Published var errorMessage: String?

    private let storage: JSONAccountsStorage
    private let legacyStorage: KeychainAccountsStorage
    private let selectedAccountKey = "TwoFAPlugin.selectedAccountID"
    private let legacySelectedAccountKey = "selectedMenuBarAccountID"

    init(
        storage: JSONAccountsStorage = JSONAccountsStorage(),
        legacyStorage: KeychainAccountsStorage = KeychainAccountsStorage()
    ) {
        self.storage = storage
        self.legacyStorage = legacyStorage
        self.storageURL = storage.fileURL
        load()
    }

    var selectedMenuBarAccount: TOTPAccount? {
        if
            let idString = UserDefaults.standard.string(forKey: selectedAccountKey)
                ?? UserDefaults.standard.string(forKey: legacySelectedAccountKey),
            let id = UUID(uuidString: idString),
            let account = accounts.first(where: { $0.id == id })
        {
            return account
        }

        return accounts.first
    }

    func isSelectedForMenuBar(_ account: TOTPAccount) -> Bool {
        selectedMenuBarAccount?.id == account.id
    }

    func selectForMenuBar(_ account: TOTPAccount) {
        UserDefaults.standard.set(account.id.uuidString, forKey: selectedAccountKey)
        UserDefaults.standard.removeObject(forKey: legacySelectedAccountKey)
        objectWillChange.send()
    }

    func add(_ account: TOTPAccount) {
        accounts.append(account)
        if accounts.count == 1 {
            selectForMenuBar(account)
        }
        persist()
    }

    func update(_ account: TOTPAccount) {
        guard let index = accounts.firstIndex(where: { $0.id == account.id }) else { return }
        accounts[index] = account
        persist()
    }

    func delete(_ account: TOTPAccount) {
        accounts.removeAll { $0.id == account.id }
        if selectedMenuBarAccount == nil {
            clearSelectedAccount()
        }
        persist()
    }

    func changeStorageLocation(to url: URL) {
        do {
            try storage.moveStorage(to: url, accounts: accounts)
            storageURL = storage.fileURL
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func useExistingStorageFile(_ url: URL) {
        do {
            accounts = try storage.useExistingStorage(at: url)
            storageURL = storage.fileURL
            clearSelectedAccount()
        } catch {
            errorMessage = "无法使用该账号文件：\(error.localizedDescription)"
        }
    }

    func accountCount(inStorageFile url: URL) throws -> Int {
        try storage.accountCount(in: url)
    }

    func code(for account: TOTPAccount, at date: Date = Date()) -> String {
        TOTPGenerator.code(for: account, at: date) ?? "------"
    }

    func remainingSeconds(for account: TOTPAccount, at date: Date = Date()) -> Int {
        TOTPGenerator.remainingSeconds(for: account, at: date)
    }

    func progress(for account: TOTPAccount, at date: Date = Date()) -> Double {
        TOTPGenerator.progress(for: account, at: date)
    }

    func copyCode(for account: TOTPAccount, at date: Date = Date()) {
        Clipboard.copy(code(for: account, at: date))
    }

    func menuBarTitle(at date: Date = Date()) -> String {
        guard let account = selectedMenuBarAccount else {
            return "2FA"
        }

        return "\(code(for: account, at: date)) \(remainingSeconds(for: account, at: date))s"
    }

    private func load() {
        do {
            if storage.fileExists {
                accounts = try storage.load()
                storageURL = storage.fileURL
                return
            }

            if storage.legacyTwoFAToolFileExists {
                let data = try Data(contentsOf: storage.legacyTwoFAToolFileURL)
                let legacyAccounts = try JSONDecoder().decode([TOTPAccount].self, from: data)
                accounts = legacyAccounts
                try storage.save(accounts)
                storageURL = storage.fileURL
                return
            }

            let legacyAccounts = try legacyStorage.load()
            accounts = legacyAccounts
            try storage.save(accounts)
            storageURL = storage.fileURL
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func persist() {
        do {
            try storage.save(accounts)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func clearSelectedAccount() {
        UserDefaults.standard.removeObject(forKey: selectedAccountKey)
        UserDefaults.standard.removeObject(forKey: legacySelectedAccountKey)
    }
}
