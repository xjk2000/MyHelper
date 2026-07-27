import AppKit
import DeveloperToolkitPlugin
import Foundation
import GitLabMenuPlugin
import MindAnchorPlugin
import SwiftUI
import TwoFAPlugin

struct HelperTool: Identifiable, Equatable {
    let id: String
    let name: String
    let subtitle: String
    let detail: String
    let systemImage: String
    let tint: Color
    let pluginKind: HelperToolPluginKind
}

enum HelperToolPluginKind: Equatable {
    case mindAnchor
    case gitLabMenu
    case developerToolkit
    case ipEnvironment
    case twoFA
}

enum HelperToolRegistry {
    static let mindAnchor = HelperTool(
        id: "mindanchor",
        name: "MindAnchor",
        subtitle: "任务捕获 / OCR / 语音转任务",
        detail: "打开完整 MindAnchor 工具窗口",
        systemImage: "target",
        tint: WidgetPalette.statusWarning,
        pluginKind: .mindAnchor
    )

    static let gitLabMenu = HelperTool(
        id: "gitlab-menu",
        name: "GitLab 工具",
        subtitle: "多实例 / 批量 clone / CI 监控",
        detail: "打开 GitLab 项目同步与流水线监控窗口",
        systemImage: "network",
        tint: WidgetPalette.statusInfo,
        pluginKind: .gitLabMenu
    )

    static let developerToolkit = HelperTool(
        id: "developer-toolkit",
        name: "研发工具包",
        subtitle: "JSON / JWT / 编码 / 正则 / 摘要",
        detail: "打开本地研发数据处理与调试工具窗口",
        systemImage: "hammer",
        tint: WidgetPalette.statusSuccess,
        pluginKind: .developerToolkit
    )

    static let ipEnvironment = HelperTool(
        id: "ip-environment",
        name: "IP 环境检测",
        subtitle: "公网 IP / ASN / 代理风险",
        detail: "检测当前出口 IP 的归属地、运营商和代理/机房风险",
        systemImage: "network.badge.shield.half.filled",
        tint: WidgetPalette.brandSecondary,
        pluginKind: .ipEnvironment
    )

    static let twoFA = HelperTool(
        id: "two-fa",
        name: "2FA 验证器",
        subtitle: "TOTP / otpauth / 二维码导入",
        detail: "管理本地 TOTP 账号并生成两步验证码",
        systemImage: "lock.shield",
        tint: WidgetPalette.statusWarning,
        pluginKind: .twoFA
    )

    static let allTools: [HelperTool] = [
        mindAnchor,
        gitLabMenu,
        developerToolkit,
        ipEnvironment,
        twoFA
    ]
}

enum HelperToolLauncher {
    @MainActor
    @discardableResult
    static func open(_ tool: HelperTool) -> Bool {
        switch tool.pluginKind {
        case .mindAnchor:
            return MindAnchorPlugin.openMainWindow()
        case .gitLabMenu:
            return GitLabMenuPlugin.openMainWindow()
        case .developerToolkit:
            return DeveloperToolkitPlugin.openMainWindow()
        case .ipEnvironment:
            return IPEnvironmentToolLauncher.openMainWindow()
        case .twoFA:
            return TwoFAPlugin.openMainWindow()
        }
    }
}
