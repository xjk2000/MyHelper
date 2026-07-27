import AppKit
import SwiftUI

public struct TwoFAMenuSummary: Equatable, Sendable {
    public let accountName: String?
    public let code: String?
    public let remainingSeconds: Int?
    public let progress: Double
    public let accountCount: Int

    public static let empty = TwoFAMenuSummary(
        accountName: nil,
        code: nil,
        remainingSeconds: nil,
        progress: 0,
        accountCount: 0
    )

    public var hasAccounts: Bool {
        accountCount > 0
    }
}

public struct TwoFAMenuItem: Identifiable, Equatable, Sendable {
    public let id: String
    public let accountName: String
    public let code: String
    public let remainingSeconds: Int
    public let progress: Double
    public let isSelected: Bool
}

public struct TwoFAMenuOverview: Equatable, Sendable {
    public let items: [TwoFAMenuItem]
    public let accountCount: Int

    public static let empty = TwoFAMenuOverview(items: [], accountCount: 0)

    public var hasAccounts: Bool {
        accountCount > 0
    }
}

public enum TwoFAPlugin {
    @MainActor
    @discardableResult
    public static func openMainWindow() -> Bool {
        TwoFARuntime.shared.showMainWindow()
        return true
    }

    @MainActor
    public static func menuSummary(at date: Date = Date()) -> TwoFAMenuSummary {
        TwoFARuntime.shared.menuSummary(at: date)
    }

    @MainActor
    public static func menuOverview(at date: Date = Date()) -> TwoFAMenuOverview {
        TwoFARuntime.shared.menuOverview(at: date)
    }

    @MainActor
    @discardableResult
    public static func copySelectedCode(at date: Date = Date()) -> Bool {
        TwoFARuntime.shared.copySelectedCode(at: date)
    }

    @MainActor
    @discardableResult
    public static func copyCode(accountID: String, at date: Date = Date()) -> Bool {
        TwoFARuntime.shared.copyCode(accountID: accountID, at: date)
    }
}

@MainActor
private final class TwoFARuntime {
    static let shared = TwoFARuntime()

    private let store = AuthenticatorStore()

    private init() {}

    func showMainWindow() {
        AccountWindowController.shared.show(store: store)
    }

    func menuSummary(at date: Date = Date()) -> TwoFAMenuSummary {
        guard let account = store.selectedMenuBarAccount else {
            return TwoFAMenuSummary(
                accountName: nil,
                code: nil,
                remainingSeconds: nil,
                progress: 0,
                accountCount: store.accounts.count
            )
        }

        return TwoFAMenuSummary(
            accountName: account.shortMenuName,
            code: store.code(for: account, at: date),
            remainingSeconds: store.remainingSeconds(for: account, at: date),
            progress: store.progress(for: account, at: date),
            accountCount: store.accounts.count
        )
    }

    func menuOverview(at date: Date = Date()) -> TwoFAMenuOverview {
        let items = store.accounts.map { account in
            TwoFAMenuItem(
                id: account.id.uuidString,
                accountName: account.displayName,
                code: store.code(for: account, at: date),
                remainingSeconds: store.remainingSeconds(for: account, at: date),
                progress: store.progress(for: account, at: date),
                isSelected: store.isSelectedForMenuBar(account)
            )
        }

        return TwoFAMenuOverview(items: items, accountCount: store.accounts.count)
    }

    func copySelectedCode(at date: Date = Date()) -> Bool {
        guard let account = store.selectedMenuBarAccount else { return false }
        store.copyCode(for: account, at: date)
        return true
    }

    func copyCode(accountID: String, at date: Date = Date()) -> Bool {
        guard
            let id = UUID(uuidString: accountID),
            let account = store.accounts.first(where: { $0.id == id })
        else {
            return false
        }

        store.copyCode(for: account, at: date)
        return true
    }
}
