import AppKit
import Foundation
import SwiftUI

@MainActor
enum IPEnvironmentToolLauncher {
    private static let runtime = IPEnvironmentToolRuntime()

    @discardableResult
    static func openMainWindow() -> Bool {
        runtime.showMainWindow()
        return true
    }
}

@MainActor
private final class IPEnvironmentToolRuntime {
    private var window: NSWindow?

    func showMainWindow() {
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 980, height: 760),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "IP 环境检测"
            window.minSize = NSSize(width: 860, height: 620)
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: IPEnvironmentToolView())
            window.center()
            self.window = window
        }

        if window?.isMiniaturized == true {
            window?.deminiaturize(nil)
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

private struct IPEnvironmentToolView: View {
    @StateObject private var viewModel = IPEnvironmentViewModel()

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .frame(minWidth: 860, minHeight: 620)
        .background(Color(nsColor: .windowBackgroundColor))
        .task {
            await viewModel.refresh()
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "network.badge.shield.half.filled")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(WidgetPalette.statusInfo)
                .frame(width: 48, height: 48)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(WidgetPalette.statusInfo.opacity(0.12))
                )

            VStack(alignment: .leading, spacing: 4) {
                Text("IP 环境检测")
                    .font(.system(size: 22, weight: .semibold))
                Text("面向 Claude / OpenAI / Gemini / X / Meta / AWS 的出口网络风控检测")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                viewModel.copySummary()
            } label: {
                Label("复制", systemImage: "doc.on.doc")
            }
            .disabled(viewModel.snapshot == nil)

            Button {
                viewModel.saveBaseline()
            } label: {
                Label("设为基准", systemImage: "checkmark.seal")
            }
            .disabled(viewModel.snapshot == nil)
            .help("将当前出口位置、ASN、ISP 和时区保存为账号常用健康环境")

            Button {
                Task { await viewModel.refresh() }
            } label: {
                Label(viewModel.isLoading ? "检测中" : "重新检测", systemImage: viewModel.isLoading ? "hourglass" : "arrow.clockwise")
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.isLoading)
        }
        .padding(.horizontal, 22)
        .padding(.vertical, 18)
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.isLoading, viewModel.snapshot == nil {
            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.small)
                Text("正在检测当前出口 IP")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let snapshot = viewModel.snapshot {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    riskSummary(snapshot)
                    vpnUsabilitySection(snapshot)
                    platformRiskSection(snapshot)
                    accountSessionPerspectiveSection(snapshot)
                    localNetworkSection(snapshot)
                    consistencySection(snapshot)
                    infoGrid(snapshot)
                    riskFlags(snapshot)
                    latencySection(snapshot)
                    rawDetails(snapshot)
                    guidance
                }
                .padding(18)
            }
        } else {
            VStack(spacing: 12) {
                Image(systemName: "wifi.exclamationmark")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(WidgetPalette.statusWarning)
                Text(viewModel.errorMessage ?? "暂时无法检测 IP 环境")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("重试") {
                    Task { await viewModel.refresh() }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(24)
        }
    }

    private func riskSummary(_ snapshot: IPEnvironmentSnapshot) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 7) {
                Text(snapshot.ip)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.62)
                Text(snapshot.locationText)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 12)

            VStack(alignment: .trailing, spacing: 6) {
                Label(snapshot.risk.title, systemImage: snapshot.risk.systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(snapshot.risk.tint)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        Capsule(style: .continuous)
                            .fill(snapshot.risk.tint.opacity(0.13))
                    )
                Text(snapshot.riskReason)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(2)
            }
            .frame(width: 230, alignment: .trailing)
        }
        .padding(16)
        .cardBackground(cornerRadius: 8)
    }

    private func vpnUsabilitySection(_ snapshot: IPEnvironmentSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: snapshot.vpnRouteState.systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(snapshot.vpnRouteState.tint)
                    .frame(width: 34, height: 34)
                    .background(
                        Circle()
                            .fill(snapshot.vpnRouteState.tint.opacity(0.12))
                    )

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text("VPN 可用性判断")
                            .font(.system(size: 13, weight: .semibold))
                        Text(snapshot.vpnRouteState.title)
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(snapshot.vpnRouteState.tint)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(snapshot.vpnRouteState.tint.opacity(0.12))
                            )
                    }
                    Text(snapshot.vpnRouteState.detail)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 10)

                VStack(alignment: .trailing, spacing: 3) {
                    Text(snapshot.ip)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Text("\(snapshot.locationText.isEmpty ? "--" : snapshot.locationText) · \(snapshot.asnText)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10)
                ],
                alignment: .leading,
                spacing: 10
            ) {
                ForEach(snapshot.serviceUsabilityAssessments) { assessment in
                    VPNServiceUsabilityCard(assessment: assessment)
                }
            }
        }
        .padding(14)
        .cardBackground(cornerRadius: 8)
    }

    private func accountSessionPerspectiveSection(_ snapshot: IPEnvironmentSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("账号会话视角")
                    .font(.system(size: 12, weight: .semibold))
                Label(snapshot.accountHealth.title, systemImage: snapshot.accountHealth.systemImage)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(snapshot.accountHealth.tint)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule(style: .continuous)
                            .fill(snapshot.accountHealth.tint.opacity(0.12))
                    )
                Spacer()
                Text(snapshot.accountHealth.reason)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10)
                ],
                alignment: .leading,
                spacing: 10
            ) {
                IPInfoCell(title: "Claude 可能显示", value: snapshot.claudeSessionLocationText)
                IPInfoCell(title: "服务端看到的 IP", value: snapshot.ip)
                IPInfoCell(title: "服务端网络归属", value: "\(snapshot.asnText) · \(snapshot.organization)")
                IPInfoCell(title: "与健康基准", value: snapshot.baselineComparisonText)
            }
        }
        .padding(14)
        .cardBackground(cornerRadius: 8)
    }

    private func platformRiskSection(_ snapshot: IPEnvironmentSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("平台风控视角")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Text("按公开地区限制、代理画像、环境一致性和连通性综合判断")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10)
                ],
                alignment: .leading,
                spacing: 10
            ) {
                ForEach(snapshot.platformAssessments) { assessment in
                    IPPlatformRiskCard(assessment: assessment)
                }
            }
        }
        .padding(14)
        .cardBackground(cornerRadius: 8)
    }

    private func infoGrid(_ snapshot: IPEnvironmentSnapshot) -> some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 10),
                GridItem(.flexible(), spacing: 10)
            ],
            alignment: .leading,
            spacing: 10
        ) {
            IPInfoCell(title: "IP 类型", value: snapshot.ipType)
            IPInfoCell(title: "ASN", value: snapshot.asnText)
            IPInfoCell(title: "运营商 / ISP", value: snapshot.isp)
            IPInfoCell(title: "组织 / Org", value: snapshot.organization)
            IPInfoCell(title: "域名", value: snapshot.domain)
            IPInfoCell(title: "时区", value: snapshot.timezone)
            IPInfoCell(title: "经纬度", value: snapshot.coordinateText)
            IPInfoCell(title: "网络类型", value: snapshot.networkTypeText)
            IPInfoCell(title: "数据源", value: snapshot.source)
        }
    }

    private func localNetworkSection(_ snapshot: IPEnvironmentSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("本机实际网络")
                .font(.system(size: 12, weight: .semibold))

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10)
                ],
                alignment: .leading,
                spacing: 10
            ) {
                IPInfoCell(title: "默认网卡", value: snapshot.localInfo.interfaceName)
                IPInfoCell(title: "局域网 IPv4", value: snapshot.localInfo.ipv4)
                IPInfoCell(title: "本机 IPv6", value: snapshot.localInfo.ipv6Text)
                IPInfoCell(title: "MAC 地址", value: snapshot.localInfo.macAddress)
                IPInfoCell(title: "网关", value: snapshot.localInfo.gateway)
                IPInfoCell(title: "主机名", value: snapshot.localInfo.hostSummary)
                IPInfoCell(title: "链路状态", value: snapshot.localInfo.linkSummary)
                IPInfoCell(title: "MTU", value: snapshot.localInfo.mtu)
            }
        }
        .padding(14)
        .cardBackground(cornerRadius: 8)
    }

    private func consistencySection(_ snapshot: IPEnvironmentSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("环境一致性")
                .font(.system(size: 12, weight: .semibold))

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10)
                ],
                alignment: .leading,
                spacing: 10
            ) {
                IPInfoCell(title: "公网 IP 二次校验", value: snapshot.publicIPConsistencyText)
                IPInfoCell(title: "时区一致性", value: snapshot.timezoneConsistencyText)
                IPInfoCell(title: "DNS 服务器", value: snapshot.localInfo.dnsText)
                IPInfoCell(title: "系统代理", value: snapshot.localInfo.proxySummary)
                IPInfoCell(title: "隧道 / VPN 接口", value: snapshot.localInfo.tunnelText)
                IPInfoCell(title: "出口路径提示", value: snapshot.routeRiskHint)
            }
        }
        .padding(14)
        .cardBackground(cornerRadius: 8)
    }

    private func riskFlags(_ snapshot: IPEnvironmentSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("风险信号")
                .font(.system(size: 12, weight: .semibold))
            HStack(spacing: 8) {
                ForEach(snapshot.flags) { flag in
                    Label(flag.title, systemImage: flag.systemImage)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(flag.isActive ? WidgetPalette.statusDanger : WidgetPalette.statusSuccess)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(
                            Capsule(style: .continuous)
                                .fill((flag.isActive ? WidgetPalette.statusDanger : WidgetPalette.statusSuccess).opacity(0.11))
                        )
                }
            }
        }
        .padding(14)
        .cardBackground(cornerRadius: 8)
    }

    private func latencySection(_ snapshot: IPEnvironmentSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("海外服务连通性")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Text("HTTPS 往返延迟")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10)
                ],
                alignment: .leading,
                spacing: 10
            ) {
                ForEach(snapshot.latencyResults) { result in
                    IPLatencyCell(result: result)
                }
            }
        }
        .padding(14)
        .cardBackground(cornerRadius: 8)
    }

    private func rawDetails(_ snapshot: IPEnvironmentSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("更多网络画像")
                .font(.system(size: 12, weight: .semibold))

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 10),
                    GridItem(.flexible(), spacing: 10)
                ],
                alignment: .leading,
                spacing: 10
            ) {
                IPInfoCell(title: "数据中心", value: snapshot.datacenterText)
                IPInfoCell(title: "公司类型", value: snapshot.companyType)
                IPInfoCell(title: "滥用评分", value: snapshot.abuserScoreText)
                IPInfoCell(title: "路由", value: snapshot.routeText)
            }
        }
        .padding(14)
        .cardBackground(cornerRadius: 8)
    }

    private var guidance: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("使用建议")
                .font(.system(size: 12, weight: .semibold))
            Text("账号风控通常会综合 IP、设备、登录地点、支付地区、行为频率等信号。这里的检测只用于判断当前出口 IP 是否像代理、VPN、Tor、机房或异常地区，不代表任何平台的最终风控结论。")
            Text("Claude 和 OpenAI 对地区限制、匿名网络和账号环境切换更敏感；AWS、X、Meta 更关注陌生地点、异常登录和已知滥用来源。更稳妥的是使用长期稳定、归属地一致、非机房的网络。")
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(.secondary)
        .padding(14)
        .cardBackground(cornerRadius: 8)
    }
}

private struct IPPlatformRiskCard: View {
    let assessment: PlatformNetworkAssessment

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Image(systemName: assessment.profile.systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(assessment.level.tint)
                    .frame(width: 24, height: 24)
                    .background(
                        Circle()
                            .fill(assessment.level.tint.opacity(0.12))
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text(assessment.profile.name)
                        .font(.system(size: 12, weight: .semibold))
                    Text(assessment.profile.strictnessText)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Text(assessment.level.title)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(assessment.level.tint)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule(style: .continuous)
                            .fill(assessment.level.tint.opacity(0.12))
                    )
            }

            Text(assessment.summary)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(2)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(assessment.reasons.prefix(3), id: \.self) { reason in
                    Label(reason, systemImage: "smallcircle.filled.circle")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 126, alignment: .topLeading)
        .padding(12)
        .cardBackground(cornerRadius: 8)
    }
}

private struct VPNServiceUsabilityCard: View {
    let assessment: VPNServiceUsabilityAssessment

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: assessment.level.systemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(assessment.level.tint)
                    .frame(width: 24, height: 24)
                    .background(
                        Circle()
                            .fill(assessment.level.tint.opacity(0.12))
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text(assessment.name)
                        .font(.system(size: 12, weight: .semibold))
                    Text(assessment.latencyText)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                Text(assessment.level.title)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(assessment.level.tint)
            }

            Text(assessment.reason)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, minHeight: 88, alignment: .topLeading)
        .padding(11)
        .cardBackground(cornerRadius: 8)
    }
}

private struct IPInfoCell: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(value.isEmpty ? "--" : value)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(3)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, minHeight: 66, alignment: .topLeading)
        .padding(12)
        .cardBackground(cornerRadius: 8)
    }
}

private struct IPLatencyCell: View {
    let result: IPLatencyResult

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: result.status.systemImage)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(result.status.tint)
                .frame(width: 26, height: 26)
                .background(
                    Circle()
                        .fill(result.status.tint.opacity(0.12))
                )

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(result.target.name)
                        .font(.system(size: 12, weight: .semibold))
                    Text(result.target.host)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                Text(result.detailText)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Text(result.latencyText)
                .font(.system(size: 14, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(result.status.tint)
        }
        .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
        .padding(10)
        .cardBackground(cornerRadius: 8)
    }
}

@MainActor
private final class IPEnvironmentViewModel: ObservableObject {
    @Published var snapshot: IPEnvironmentSnapshot?
    @Published var isLoading = false
    @Published var errorMessage: String?

    private let service = IPEnvironmentService()

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil

        do {
            snapshot = try await service.load()
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func copySummary() {
        guard let snapshot else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(snapshot.summaryText, forType: .string)
    }

    func saveBaseline() {
        guard let snapshot else { return }
        NetworkHealthBaselineStore.save(snapshot.makeBaseline())
        objectWillChange.send()
    }
}

private struct IPEnvironmentService {
    func load() async throws -> IPEnvironmentSnapshot {
        async let riskDTO = loadRiskSignals()
        async let latencyResults = loadLatencyResults()
        async let publicIPProbe = loadPublicIPProbe()
        let localInfo = LocalNetworkReader.load()

        var request = URLRequest(
            url: URL(string: "https://ipwho.is/")!,
            cachePolicy: .reloadIgnoringLocalAndRemoteCacheData,
            timeoutInterval: 12
        )
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("MyHelper/1.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw IPEnvironmentError.unavailable
        }

        let dto = try JSONDecoder().decode(IPWhoIsResponse.self, from: data)
        guard dto.success != false, let ip = dto.ip, !ip.isEmpty else {
            throw IPEnvironmentError.message(dto.message)
        }

        return IPEnvironmentSnapshot(
            dto: dto,
            riskDTO: try? await riskDTO,
            latencyResults: await latencyResults,
            publicIPProbe: try? await publicIPProbe,
            localInfo: localInfo
        )
    }

    private func loadRiskSignals() async throws -> IPAPIIsResponse {
        var request = URLRequest(
            url: URL(string: "https://api.ipapi.is/")!,
            cachePolicy: .reloadIgnoringLocalAndRemoteCacheData,
            timeoutInterval: 12
        )
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("MyHelper/1.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw IPEnvironmentError.unavailable
        }
        return try JSONDecoder().decode(IPAPIIsResponse.self, from: data)
    }

    private func loadPublicIPProbe() async throws -> PublicIPProbe {
        var request = URLRequest(
            url: URL(string: "https://api64.ipify.org?format=json")!,
            cachePolicy: .reloadIgnoringLocalAndRemoteCacheData,
            timeoutInterval: 8
        )
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("MyHelper/1.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw IPEnvironmentError.unavailable
        }
        let dto = try JSONDecoder().decode(PublicIPProbeResponse.self, from: data)
        return PublicIPProbe(source: "api64.ipify.org", ip: dto.ip)
    }

    private func loadLatencyResults() async -> [IPLatencyResult] {
        await withTaskGroup(of: IPLatencyResult.self) { group in
            for target in IPLatencyTarget.defaults {
                group.addTask {
                    await IPLatencyProbe.measure(target)
                }
            }

            var results: [IPLatencyResult] = []
            for await result in group {
                results.append(result)
            }
            return results.sorted { lhs, rhs in
                lhs.target.order < rhs.target.order
            }
        }
    }
}

private enum IPEnvironmentError: LocalizedError {
    case unavailable
    case message(String?)

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "IP 查询服务暂时不可用"
        case let .message(message):
            return message?.isEmpty == false ? message : "IP 查询服务返回了无效结果"
        }
    }
}

private struct IPLatencyTarget: Identifiable, Equatable {
    let order: Int
    let name: String
    let host: String
    let url: URL

    var id: Int { order }

    static let defaults: [IPLatencyTarget] = [
        IPLatencyTarget(order: 0, name: "Claude", host: "claude.ai", url: URL(string: "https://claude.ai/")!),
        IPLatencyTarget(order: 1, name: "Anthropic API", host: "api.anthropic.com", url: URL(string: "https://api.anthropic.com/")!),
        IPLatencyTarget(order: 2, name: "OpenAI / ChatGPT", host: "chatgpt.com", url: URL(string: "https://chatgpt.com/")!),
        IPLatencyTarget(order: 3, name: "OpenAI API", host: "api.openai.com", url: URL(string: "https://api.openai.com/v1/models")!),
        IPLatencyTarget(order: 4, name: "Gemini", host: "gemini.google.com", url: URL(string: "https://gemini.google.com/")!),
        IPLatencyTarget(order: 5, name: "Google", host: "google.com", url: URL(string: "https://www.google.com/generate_204")!),
        IPLatencyTarget(order: 6, name: "X", host: "x.com", url: URL(string: "https://x.com/")!),
        IPLatencyTarget(order: 7, name: "Meta", host: "facebook.com", url: URL(string: "https://www.facebook.com/")!),
        IPLatencyTarget(order: 8, name: "AWS Console", host: "console.aws.amazon.com", url: URL(string: "https://console.aws.amazon.com/")!),
        IPLatencyTarget(order: 9, name: "Telegram", host: "web.telegram.org", url: URL(string: "https://web.telegram.org/")!)
    ]
}

private struct IPLatencyResult: Identifiable, Equatable {
    let target: IPLatencyTarget
    let durationMs: Int?
    let httpStatus: Int?
    let errorMessage: String?

    var id: Int { target.order }

    var status: IPLatencyStatus {
        guard let durationMs else { return .failed }
        if durationMs <= 1_500 { return .good }
        if durationMs <= 5_000 { return .slow }
        return .poor
    }

    var latencyText: String {
        guard let durationMs else { return "--" }
        return "\(durationMs)ms"
    }

    var detailText: String {
        if let httpStatus {
            return "HTTP \(httpStatus) · \(status.title)"
        }
        return errorMessage ?? status.title
    }
}

private enum IPLatencyStatus: Equatable {
    case good
    case slow
    case poor
    case failed

    var severity: Int {
        switch self {
        case .good: return 0
        case .slow: return 1
        case .poor: return 2
        case .failed: return 3
        }
    }

    var title: String {
        switch self {
        case .good: return "可达"
        case .slow: return "偏慢"
        case .poor: return "很慢"
        case .failed: return "不可达"
        }
    }

    var systemImage: String {
        switch self {
        case .good: return "checkmark.circle"
        case .slow: return "clock"
        case .poor: return "exclamationmark.triangle"
        case .failed: return "xmark.octagon"
        }
    }

    var tint: Color {
        switch self {
        case .good: return WidgetPalette.statusSuccess
        case .slow: return WidgetPalette.statusWarning
        case .poor: return WidgetPalette.statusWarning
        case .failed: return WidgetPalette.statusDanger
        }
    }
}

private enum IPLatencyProbe {
    static func measure(_ target: IPLatencyTarget) async -> IPLatencyResult {
        var request = URLRequest(
            url: target.url,
            cachePolicy: .reloadIgnoringLocalAndRemoteCacheData,
            timeoutInterval: 8
        )
        request.httpMethod = "HEAD"
        request.setValue("MyHelper/1.0", forHTTPHeaderField: "User-Agent")

        let startedAt = Date()
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            let elapsed = max(0, Int(Date().timeIntervalSince(startedAt) * 1_000))
            let status = (response as? HTTPURLResponse)?.statusCode
            return IPLatencyResult(
                target: target,
                durationMs: elapsed,
                httpStatus: status,
                errorMessage: nil
            )
        } catch {
            return IPLatencyResult(
                target: target,
                durationMs: nil,
                httpStatus: nil,
                errorMessage: shortNetworkError(error)
            )
        }
    }

    private static func shortNetworkError(_ error: Error) -> String {
        let nsError = error as NSError
        switch nsError.code {
        case NSURLErrorTimedOut:
            return "连接超时"
        case NSURLErrorCannotFindHost:
            return "DNS 失败"
        case NSURLErrorCannotConnectToHost, NSURLErrorNetworkConnectionLost:
            return "连接失败"
        case NSURLErrorNotConnectedToInternet:
            return "无网络"
        default:
            return nsError.localizedDescription
        }
    }
}

private struct LocalNetworkInfo: Equatable {
    let interfaceName: String
    let gateway: String
    let ipv4: String
    let ipv6Addresses: [String]
    let macAddress: String
    let mtu: String
    let media: String
    let status: String
    let dnsServers: [String]
    let proxySummary: String
    let tunnelInterfaces: [String]
    let systemTimezone: String
    let computerName: String
    let localHostName: String
    let hostName: String

    var ipv6Text: String {
        ipv6Addresses.isEmpty ? "--" : ipv6Addresses.joined(separator: "\n")
    }

    var hostSummary: String {
        [computerName, localHostName, hostName]
            .filter { !$0.isEmpty && $0 != "--" }
            .joined(separator: " / ")
    }

    var linkSummary: String {
        [status, media]
            .filter { !$0.isEmpty && $0 != "--" }
            .joined(separator: " · ")
    }

    var dnsText: String {
        dnsServers.isEmpty ? "--" : dnsServers.joined(separator: "\n")
    }

    var tunnelText: String {
        tunnelInterfaces.isEmpty ? "未发现活跃隧道接口" : tunnelInterfaces.joined(separator: "\n")
    }

    static let empty = LocalNetworkInfo(
        interfaceName: "--",
        gateway: "--",
        ipv4: "--",
        ipv6Addresses: [],
        macAddress: "--",
        mtu: "--",
        media: "--",
        status: "--",
        dnsServers: [],
        proxySummary: "--",
        tunnelInterfaces: [],
        systemTimezone: "--",
        computerName: "--",
        localHostName: "--",
        hostName: "--"
    )
}

private enum LocalNetworkReader {
    static func load() -> LocalNetworkInfo {
        let route = shell("/sbin/route -n get default 2>/dev/null")
        let interfaceName = routeValue("interface", in: route)
        let gateway = routeValue("gateway", in: route)
        let allIfconfig = shell("/sbin/ifconfig")
        let safeInterface = interfaceName.range(of: #"^[A-Za-z0-9]+$"#, options: .regularExpression) != nil
            ? interfaceName
            : ""
        let ifconfig = safeInterface.isEmpty
            ? allIfconfig
            : shell("/sbin/ifconfig \(safeInterface)")

        return LocalNetworkInfo(
            interfaceName: interfaceName.isEmpty ? "--" : interfaceName,
            gateway: gateway.isEmpty ? "--" : gateway,
            ipv4: firstIPv4(in: ifconfig),
            ipv6Addresses: ipv6Addresses(in: ifconfig),
            macAddress: firstValue(after: "ether", in: ifconfig),
            mtu: mtu(in: ifconfig),
            media: lineValue("media", in: ifconfig),
            status: lineValue("status", in: ifconfig),
            dnsServers: dnsServers(in: shell("scutil --dns 2>/dev/null")),
            proxySummary: proxySummary(in: shell("scutil --proxy 2>/dev/null")),
            tunnelInterfaces: tunnelInterfaces(in: allIfconfig),
            systemTimezone: TimeZone.current.identifier,
            computerName: shell("scutil --get ComputerName 2>/dev/null").trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "--",
            localHostName: shell("scutil --get LocalHostName 2>/dev/null").trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "--",
            hostName: shell("/bin/hostname 2>/dev/null").trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "--"
        )
    }

    private static func routeValue(_ key: String, in text: String) -> String {
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("\(key):") else { continue }
            return trimmed
                .dropFirst(key.count + 1)
                .trimmingCharacters(in: .whitespaces)
        }
        return ""
    }

    private static func lineValue(_ key: String, in text: String) -> String {
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("\(key):") else { continue }
            return trimmed
                .dropFirst(key.count + 1)
                .trimmingCharacters(in: .whitespaces)
        }
        return "--"
    }

    private static func firstValue(after token: String, in text: String) -> String {
        for line in text.components(separatedBy: .newlines) {
            let parts = line.trimmingCharacters(in: .whitespaces).split(separator: " ")
            guard parts.first.map(String.init) == token, parts.count > 1 else { continue }
            return String(parts[1])
        }
        return "--"
    }

    private static func firstIPv4(in text: String) -> String {
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("inet ") else { continue }
            let parts = trimmed.split(separator: " ")
            guard parts.count > 1 else { continue }
            let value = String(parts[1])
            if value != "127.0.0.1" { return value }
        }
        return "--"
    }

    private static func ipv6Addresses(in text: String) -> [String] {
        text.components(separatedBy: .newlines).compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("inet6 ") else { return nil }
            let parts = trimmed.split(separator: " ")
            guard parts.count > 1 else { return nil }
            let value = String(parts[1])
            guard value != "::1" else { return nil }
            return value
        }
    }

    private static func mtu(in text: String) -> String {
        guard let firstLine = text.components(separatedBy: .newlines).first,
              let range = firstLine.range(of: #"mtu\s+\d+"#, options: .regularExpression) else {
            return "--"
        }
        return firstLine[range]
            .replacingOccurrences(of: "mtu", with: "")
            .trimmingCharacters(in: .whitespaces)
    }

    private static func dnsServers(in text: String) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("nameserver[") else { continue }
            guard let separator = trimmed.range(of: ":") else { continue }
            let value = trimmed[separator.upperBound...]
                .trimmingCharacters(in: .whitespaces)
            guard !value.isEmpty, !seen.contains(value) else { continue }
            seen.insert(value)
            result.append(value)
            if result.count >= 6 { break }
        }
        return result
    }

    private static func proxySummary(in text: String) -> String {
        let http = dictionaryValue("HTTPEnable", in: text) == "1"
        let https = dictionaryValue("HTTPSEnable", in: text) == "1"
        let socks = dictionaryValue("SOCKSEnable", in: text) == "1"
        let pac = dictionaryValue("ProxyAutoConfigEnable", in: text) == "1"

        var enabled: [String] = []
        if http { enabled.append("HTTP") }
        if https { enabled.append("HTTPS") }
        if socks { enabled.append("SOCKS") }
        if pac { enabled.append("PAC") }

        guard !enabled.isEmpty else { return "未开启系统代理" }
        return enabled.joined(separator: " / ")
    }

    private static func dictionaryValue(_ key: String, in text: String) -> String {
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("\(key) :") else { continue }
            return trimmed
                .replacingOccurrences(of: "\(key) :", with: "")
                .trimmingCharacters(in: .whitespaces)
        }
        return ""
    }

    private static func tunnelInterfaces(in text: String) -> [String] {
        var result: [String] = []
        var currentName: String?
        var currentMTU: String?
        var currentIPv4: String?

        func flush() {
            guard let currentName else { return }
            var parts = [currentName]
            if let currentIPv4 { parts.append(currentIPv4) }
            if let currentMTU { parts.append("MTU \(currentMTU)") }
            result.append(parts.joined(separator: " · "))
        }

        for line in text.components(separatedBy: .newlines) {
            if let range = line.range(of: #"^(utun|ppp|ipsec|wg|tun|tap)\d*:"#, options: .regularExpression) {
                flush()
                currentName = String(line[range]).replacingOccurrences(of: ":", with: "")
                currentMTU = mtu(in: line)
                currentIPv4 = nil
                continue
            }

            guard currentName != nil else { continue }
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("inet ") {
                let parts = trimmed.split(separator: " ")
                if parts.count > 1 {
                    currentIPv4 = String(parts[1])
                }
            }
        }

        flush()
        return result
    }

    private static func shell(_ command: String) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8) ?? ""
        } catch {
            return ""
        }
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }

    var nilFallback: String {
        isEmpty ? "--" : self
    }
}

private struct IPEnvironmentSnapshot: Equatable {
    let ip: String
    let ipType: String
    let country: String
    let region: String
    let city: String
    let asn: Int?
    let isp: String
    let organization: String
    let domain: String
    let security: IPWhoIsSecurity
    let source: String
    let timezone: String
    let latitude: Double?
    let longitude: Double?
    let datacenterText: String
    let companyType: String
    let abuserScoreText: String
    let routeText: String
    let latencyResults: [IPLatencyResult]
    let publicIPProbe: PublicIPProbe?
    let localInfo: LocalNetworkInfo

    init(
        dto: IPWhoIsResponse,
        riskDTO: IPAPIIsResponse?,
        latencyResults: [IPLatencyResult],
        publicIPProbe: PublicIPProbe?,
        localInfo: LocalNetworkInfo
    ) {
        ip = dto.ip ?? "--"
        ipType = dto.type ?? "--"
        country = dto.country ?? ""
        region = dto.region ?? ""
        city = dto.city ?? ""
        asn = dto.connection?.asn ?? riskDTO?.asn?.asn
        isp = dto.connection?.isp ?? riskDTO?.asn?.descr ?? "--"
        organization = dto.connection?.org ?? riskDTO?.company?.name ?? riskDTO?.datacenter?.name ?? "--"
        domain = dto.connection?.domain ?? riskDTO?.company?.domain ?? riskDTO?.datacenter?.domain ?? "--"
        security = IPWhoIsSecurity(primary: dto.security, riskDTO: riskDTO)
        source = riskDTO == nil ? "ipwho.is" : "ipwho.is + ipapi.is"
        timezone = dto.timezone?.id ?? "--"
        latitude = dto.latitude
        longitude = dto.longitude
        datacenterText = riskDTO?.datacenter?.displayName ?? "--"
        companyType = riskDTO?.company?.type ?? "--"
        abuserScoreText = riskDTO?.company?.abuserScore ?? riskDTO?.asn?.abuserScore ?? "--"
        routeText = riskDTO?.asn?.route ?? "--"
        self.latencyResults = latencyResults
        self.publicIPProbe = publicIPProbe
        self.localInfo = localInfo
    }

    var locationText: String {
        [country, region, city].filter { !$0.isEmpty }.joined(separator: " / ")
    }

    var asnText: String {
        asn.map { "AS\($0)" } ?? "--"
    }

    var coordinateText: String {
        guard let latitude, let longitude else { return "--" }
        return String(format: "%.4f, %.4f", latitude, longitude)
    }

    var networkTypeText: String {
        if security.proxy == true { return "代理 / Proxy" }
        if security.vpn == true { return "VPN" }
        if security.tor == true { return "Tor" }
        if security.hosting == true { return "数据中心 / Hosting" }
        return "未发现特殊匿名网络"
    }

    var publicIPConsistencyText: String {
        guard let publicIPProbe else { return "二次校验失败" }
        let result = publicIPProbe.ip == ip ? "一致" : "不一致"
        return "\(result)：\(publicIPProbe.ip)（\(publicIPProbe.source)）"
    }

    var timezoneConsistencyText: String {
        guard timezone != "--", localInfo.systemTimezone != "--" else { return "--" }
        if timezone == localInfo.systemTimezone {
            return "一致：\(timezone)"
        }
        return "不一致：系统 \(localInfo.systemTimezone) / IP \(timezone)"
    }

    var routeRiskHint: String {
        var hints: [String] = []
        if localInfo.proxySummary != "未开启系统代理" {
            hints.append("系统代理已开启")
        }
        if !localInfo.tunnelInterfaces.isEmpty {
            hints.append("存在隧道接口")
        }
        if localInfo.ipv4.hasPrefix("10.")
            || localInfo.ipv4.hasPrefix("172.")
            || localInfo.ipv4.hasPrefix("192.168.") {
            hints.append("本机为私网地址")
        }
        if publicIPProbe?.ip != nil, publicIPProbe?.ip != ip {
            hints.append("公网 IP 源不一致")
        }
        return hints.isEmpty ? "未发现明显路径异常" : hints.joined(separator: "；")
    }

    var flags: [IPRiskFlag] {
        [
            IPRiskFlag(title: "代理", systemImage: "point.3.connected.trianglepath.dotted", isActive: security.proxy == true),
            IPRiskFlag(title: "VPN", systemImage: "lock.shield", isActive: security.vpn == true),
            IPRiskFlag(title: "Tor", systemImage: "network", isActive: security.tor == true),
            IPRiskFlag(title: "机房", systemImage: "server.rack", isActive: security.hosting == true),
            IPRiskFlag(title: "滥用", systemImage: "exclamationmark.triangle", isActive: security.abuser == true),
            IPRiskFlag(title: "匿名", systemImage: "eye.slash", isActive: security.anonymous == true)
        ]
    }

    var risk: IPEnvironmentRisk {
        if security.proxy == true || security.vpn == true || security.tor == true || security.anonymous == true || security.abuser == true {
            return .high
        }
        if security.hosting == true || looksLikeCloudProvider {
            return .medium
        }
        return .low
    }

    var platformAssessments: [PlatformNetworkAssessment] {
        PlatformNetworkProfile.defaults.map { profile in
            PlatformNetworkAssessment(profile: profile, snapshot: self)
        }
    }

    var serviceUsabilityAssessments: [VPNServiceUsabilityAssessment] {
        PlatformNetworkProfile.defaults.map { profile in
            VPNServiceUsabilityAssessment(profile: profile, snapshot: self)
        }
    }

    var vpnRouteState: VPNRouteState {
        let hasLocalTunnel = !localInfo.tunnelInterfaces.isEmpty
        let hasSystemProxy = localInfo.proxySummary != "未开启系统代理"
        let hasRemoteProxySignal = security.vpn == true || security.proxy == true || security.anonymous == true
        let hasDatacenterExit = security.hosting == true || looksLikeCloudProvider

        if hasRemoteProxySignal {
            return .active("出口 IP 已被识别为 VPN/代理/匿名网络，需要重点看下方平台可用性。")
        }
        if hasLocalTunnel || hasSystemProxy {
            return .active("本机存在隧道接口或系统代理，但出口 IP 未被识别为高匿名网络。")
        }
        if hasDatacenterExit {
            return .indirect("出口更像云厂商或托管网络，不一定是 VPN，但对严风控账号仍需谨慎。")
        }
        return .direct("未发现明显 VPN/代理路径；如果你确实开了 VPN，当前出口画像相对干净。")
    }

    var riskReason: String {
        switch risk {
        case .low:
            return "未发现明显代理或机房信号"
        case .medium:
            return "存在云厂商或托管网络特征"
        case .high:
            return "命中代理/VPN/Tor/匿名/滥用信号"
        }
    }

    var summaryText: String {
        [
            "IP：\(ip)",
            "风险：\(risk.title)",
            "位置：\(locationText.isEmpty ? "--" : locationText)",
            "ASN：\(asnText)",
            "ISP：\(isp)",
            "Org：\(organization)",
            "Local IPv4：\(localInfo.ipv4)",
            "Interface：\(localInfo.interfaceName)",
            "MAC：\(localInfo.macAddress)",
            "Gateway：\(localInfo.gateway)",
            "System Timezone：\(localInfo.systemTimezone)",
            "IP Timezone：\(timezone)",
            "DNS：\(localInfo.dnsText.replacingOccurrences(of: "\n", with: ", "))",
            "System Proxy：\(localInfo.proxySummary)",
            "Tunnel：\(localInfo.tunnelText.replacingOccurrences(of: "\n", with: ", "))",
            "Public IP Check：\(publicIPConsistencyText)",
            "Risk Proxy：\(security.proxyText)",
            "VPN：\(security.vpnText)",
            "Tor：\(security.torText)",
            "Hosting：\(security.hostingText)",
            "Abuser：\(security.abuserText)",
            "Latency：\(latencyResults.map { "\($0.target.name)=\($0.latencyText)" }.joined(separator: ", "))",
            "Account Session Location：\(claudeSessionLocationText)",
            "Baseline：\(baselineComparisonText)",
            "Source：\(source)"
        ].joined(separator: "\n")
    }

    fileprivate var looksLikeCloudProvider: Bool {
        let haystack = "\(isp) \(organization) \(domain)".lowercased()
        let keywords = [
            "amazon", "aws", "google", "cloudflare", "microsoft", "azure",
            "digitalocean", "linode", "vultr", "ovh", "hetzner", "tencent",
            "alibaba", "aliyun", "huawei", "oracle", "cloud", "hosting", "data center"
        ]
        return keywords.contains { haystack.contains($0) }
    }

    var claudeSessionLocationText: String {
        let cityRegionCountry = [city, region, country]
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
        return cityRegionCountry.isEmpty ? "--" : cityRegionCountry
    }

    var baselineComparisonText: String {
        guard let baseline = NetworkHealthBaselineStore.load() else {
            return "未设置基准；可点击“设为基准”保存当前健康环境"
        }

        var changes: [String] = []
        if baseline.country != country {
            changes.append("国家 \(baseline.country.nilFallback) -> \(country.nilFallback)")
        } else if baseline.region != region || baseline.city != city {
            changes.append("城市/地区变化")
        }
        if baseline.asn != asn {
            changes.append("ASN \(baseline.asnText) -> \(asnText)")
        }
        if baseline.timezone != timezone {
            changes.append("时区 \(baseline.timezone.nilFallback) -> \(timezone.nilFallback)")
        }
        if baseline.ip != ip {
            changes.append("IP 已变化")
        }

        guard !changes.isEmpty else {
            return "一致：\(baseline.locationText) · \(baseline.asnText)"
        }
        return changes.joined(separator: "；")
    }

    var accountHealth: AccountNetworkHealth {
        let baseline = NetworkHealthBaselineStore.load()
        let claude = latencyResults.first { $0.target.name == "Claude" }
        let codex = latencyResults.first { $0.target.name == "OpenAI / ChatGPT" }
        let failedSensitiveService = [claude, codex].contains { result in
            result?.status == .failed
        }

        if risk == .high {
            return .high("命中代理/VPN/Tor/匿名/滥用信号")
        }
        if let baseline, baseline.country != country {
            return .high("国家与健康基准不一致")
        }
        if failedSensitiveService {
            return .high("Claude 或 Codex 连通异常")
        }
        if risk == .medium {
            return .medium("存在机房或云厂商特征")
        }
        if let baseline, baseline.asn != asn {
            return .medium("ASN 与健康基准不同")
        }
        if timezoneConsistencyText.hasPrefix("不一致") {
            return .medium("系统时区与 IP 时区不同")
        }
        return .low("位置、ASN、代理风险和服务连通性较稳定")
    }

    func makeBaseline() -> NetworkHealthBaseline {
        NetworkHealthBaseline(
            savedAt: Date(),
            ip: ip,
            country: country,
            region: region,
            city: city,
            asn: asn,
            isp: isp,
            organization: organization,
            timezone: timezone
        )
    }
}

private struct PlatformNetworkProfile: Identifiable, Equatable {
    enum Strictness: Equatable {
        case extreme
        case high
        case medium

        var text: String {
            switch self {
            case .extreme: return "极严风控"
            case .high: return "高敏感"
            case .medium: return "中高敏感"
            }
        }
    }

    let id: String
    let name: String
    let systemImage: String
    let strictness: Strictness
    let targetNames: [String]
    let restrictedCountries: Set<String>
    let highRiskForDatacenter: Bool
    let highRiskForVPN: Bool

    var strictnessText: String { strictness.text }

    static let aiRestrictedCountries: Set<String> = [
        "China", "Russia", "Iran", "North Korea", "Syria", "Cuba"
    ]

    static let defaults: [PlatformNetworkProfile] = [
        PlatformNetworkProfile(
            id: "claude",
            name: "Claude",
            systemImage: "sparkles",
            strictness: .extreme,
            targetNames: ["Claude", "Anthropic API"],
            restrictedCountries: aiRestrictedCountries,
            highRiskForDatacenter: true,
            highRiskForVPN: true
        ),
        PlatformNetworkProfile(
            id: "openai",
            name: "OpenAI",
            systemImage: "brain.head.profile",
            strictness: .high,
            targetNames: ["OpenAI / ChatGPT", "OpenAI API"],
            restrictedCountries: aiRestrictedCountries,
            highRiskForDatacenter: false,
            highRiskForVPN: false
        ),
        PlatformNetworkProfile(
            id: "gemini",
            name: "Gemini",
            systemImage: "diamond",
            strictness: .high,
            targetNames: ["Gemini", "Google"],
            restrictedCountries: aiRestrictedCountries,
            highRiskForDatacenter: false,
            highRiskForVPN: false
        ),
        PlatformNetworkProfile(
            id: "x",
            name: "X",
            systemImage: "message",
            strictness: .medium,
            targetNames: ["X"],
            restrictedCountries: [],
            highRiskForDatacenter: false,
            highRiskForVPN: false
        ),
        PlatformNetworkProfile(
            id: "meta",
            name: "Meta",
            systemImage: "person.2",
            strictness: .medium,
            targetNames: ["Meta"],
            restrictedCountries: [],
            highRiskForDatacenter: false,
            highRiskForVPN: false
        ),
        PlatformNetworkProfile(
            id: "aws",
            name: "AWS",
            systemImage: "server.rack",
            strictness: .high,
            targetNames: ["AWS Console"],
            restrictedCountries: ["Iran", "North Korea", "Syria", "Cuba"],
            highRiskForDatacenter: false,
            highRiskForVPN: false
        )
    ]
}

private struct VPNServiceUsabilityAssessment: Identifiable, Equatable {
    let id: String
    let name: String
    let level: VPNServiceUsabilityLevel
    let latencyText: String
    let reason: String

    init(profile: PlatformNetworkProfile, snapshot: IPEnvironmentSnapshot) {
        id = profile.id
        name = profile.name

        let targetResults = profile.targetNames.compactMap { targetName in
            snapshot.latencyResults.first { $0.target.name == targetName }
        }
        let failedResults = targetResults.filter { $0.status == .failed }
        let reachableResults = targetResults.filter { $0.status != .failed }
        let worstReachableStatus = reachableResults.map(\.status).maxBySeverity
        let platformAssessment = PlatformNetworkAssessment(profile: profile, snapshot: snapshot)

        if targetResults.isEmpty {
            level = .unknown
            latencyText = "未配置探测目标"
            reason = "缺少该平台的连通性探测项"
            return
        }

        if failedResults.count == targetResults.count {
            level = .unusable
            latencyText = failedResults.map { "\($0.target.name)：\($0.detailText)" }.joined(separator: " / ")
            reason = "当前 VPN/网络无法连通该平台入口，不建议用于登录。"
            return
        }

        let latencyParts = targetResults.map { result in
            "\(result.target.name)：\(result.latencyText)"
        }
        latencyText = latencyParts.joined(separator: " / ")

        if platformAssessment.level == .high {
            level = .risky
            reason = platformAssessment.reasons.first ?? "连通但存在较高风控风险"
            return
        }

        if failedResults.isEmpty == false {
            level = .risky
            reason = "部分入口不可达：\(failedResults.map { $0.target.name }.joined(separator: "、"))"
            return
        }

        if worstReachableStatus == .poor || worstReachableStatus == .slow {
            level = .degraded
            reason = "可以连通，但延迟偏高，使用时可能触发超时或体验异常。"
            return
        }

        if platformAssessment.level == .medium {
            level = .degraded
            reason = platformAssessment.reasons.first ?? "可用但存在需要留意的网络画像"
            return
        }

        level = .usable
        reason = "入口可达，未命中明显高风险网络画像。"
    }
}

private enum VPNServiceUsabilityLevel: Equatable {
    case usable
    case degraded
    case risky
    case unusable
    case unknown

    var title: String {
        switch self {
        case .usable: return "可用"
        case .degraded: return "慎用"
        case .risky: return "高风险"
        case .unusable: return "不可用"
        case .unknown: return "未知"
        }
    }

    var systemImage: String {
        switch self {
        case .usable: return "checkmark.circle"
        case .degraded: return "exclamationmark.triangle"
        case .risky: return "shield.slash"
        case .unusable: return "xmark.octagon"
        case .unknown: return "questionmark.circle"
        }
    }

    var tint: Color {
        switch self {
        case .usable: return WidgetPalette.statusSuccess
        case .degraded: return WidgetPalette.statusWarning
        case .risky: return WidgetPalette.statusDanger
        case .unusable: return WidgetPalette.statusDanger
        case .unknown: return WidgetPalette.statusInfo
        }
    }
}

private enum VPNRouteState: Equatable {
    case direct(String)
    case indirect(String)
    case active(String)

    var title: String {
        switch self {
        case .direct: return "未见 VPN 特征"
        case .indirect: return "疑似托管出口"
        case .active: return "检测到代理路径"
        }
    }

    var detail: String {
        switch self {
        case let .direct(detail), let .indirect(detail), let .active(detail):
            return detail
        }
    }

    var systemImage: String {
        switch self {
        case .direct: return "network"
        case .indirect: return "server.rack"
        case .active: return "point.3.connected.trianglepath.dotted"
        }
    }

    var tint: Color {
        switch self {
        case .direct: return WidgetPalette.statusSuccess
        case .indirect: return WidgetPalette.statusWarning
        case .active: return WidgetPalette.statusInfo
        }
    }
}

private extension Array where Element == IPLatencyStatus {
    var maxBySeverity: IPLatencyStatus? {
        sorted { lhs, rhs in
            lhs.severity > rhs.severity
        }.first
    }
}

private struct PlatformNetworkAssessment: Identifiable, Equatable {
    let profile: PlatformNetworkProfile
    let level: PlatformNetworkRiskLevel
    let reasons: [String]

    var id: String { profile.id }

    var summary: String {
        switch level {
        case .low:
            return "当前出口网络更接近稳定账号环境"
        case .medium:
            return "存在可能触发额外验证的环境差异"
        case .high:
            return "不建议在该环境执行登录、支付或关键账号操作"
        }
    }

    init(profile: PlatformNetworkProfile, snapshot: IPEnvironmentSnapshot) {
        self.profile = profile

        var highReasons: [String] = []
        var mediumReasons: [String] = []

        if profile.restrictedCountries.contains(snapshot.country) {
            highReasons.append("当前国家/地区可能不在官方支持范围")
        }

        if snapshot.security.tor == true {
            highReasons.append("Tor 出口")
        }
        if snapshot.security.proxy == true || snapshot.security.anonymous == true {
            highReasons.append("代理或匿名网络")
        }
        if snapshot.security.abuser == true {
            highReasons.append("IP 命中滥用画像")
        }
        if snapshot.security.vpn == true {
            if profile.highRiskForVPN {
                highReasons.append("VPN 对该平台风险较高")
            } else {
                mediumReasons.append("VPN 可能触发额外验证")
            }
        }
        if snapshot.security.hosting == true || snapshot.looksLikeCloudProvider {
            if profile.highRiskForDatacenter {
                highReasons.append("机房/云厂商 IP 对该平台风险较高")
            } else {
                mediumReasons.append("机房或云厂商 IP")
            }
        }

        let failedTargets = profile.targetNames.compactMap { targetName in
            snapshot.latencyResults.first { $0.target.name == targetName && $0.status == .failed }?.target.name
        }
        if !failedTargets.isEmpty {
            highReasons.append("\(failedTargets.joined(separator: "、")) 不可达")
        }

        let slowTargets = profile.targetNames.compactMap { targetName in
            snapshot.latencyResults.first { $0.target.name == targetName && ($0.status == .slow || $0.status == .poor) }?.target.name
        }
        if !slowTargets.isEmpty {
            mediumReasons.append("\(slowTargets.joined(separator: "、")) 延迟异常")
        }

        if let baseline = NetworkHealthBaselineStore.load() {
            if baseline.country != snapshot.country {
                highReasons.append("国家与健康基准不一致")
            } else if baseline.asn != snapshot.asn {
                mediumReasons.append("ASN 与健康基准不同")
            }
        }

        if snapshot.timezoneConsistencyText.hasPrefix("不一致") {
            mediumReasons.append("系统时区与 IP 时区不一致")
        }
        if snapshot.publicIPProbe?.ip != nil, snapshot.publicIPProbe?.ip != snapshot.ip {
            mediumReasons.append("公网 IP 多源校验不一致")
        }
        if snapshot.localInfo.proxySummary != "未开启系统代理" {
            mediumReasons.append("系统代理已开启")
        }
        if !snapshot.localInfo.tunnelInterfaces.isEmpty {
            mediumReasons.append("存在隧道/VPN 接口")
        }

        if !highReasons.isEmpty {
            level = .high
            reasons = highReasons + mediumReasons
        } else if !mediumReasons.isEmpty {
            level = .medium
            reasons = mediumReasons
        } else {
            level = .low
            reasons = ["未命中代理、匿名、机房、地区或连通性异常"]
        }
    }
}

private enum PlatformNetworkRiskLevel: Equatable {
    case low
    case medium
    case high

    var title: String {
        switch self {
        case .low: return "可用"
        case .medium: return "留意"
        case .high: return "高风险"
        }
    }

    var tint: Color {
        switch self {
        case .low: return WidgetPalette.statusSuccess
        case .medium: return WidgetPalette.statusWarning
        case .high: return WidgetPalette.statusDanger
        }
    }
}

private struct NetworkHealthBaseline: Codable, Equatable {
    let savedAt: Date
    let ip: String
    let country: String
    let region: String
    let city: String
    let asn: Int?
    let isp: String
    let organization: String
    let timezone: String

    var locationText: String {
        [city, region, country]
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    var asnText: String {
        asn.map { "AS\($0)" } ?? "--"
    }
}

private enum NetworkHealthBaselineStore {
    private static let key = "IPEnvironmentTool.networkHealthBaseline"

    static func load() -> NetworkHealthBaseline? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(NetworkHealthBaseline.self, from: data)
    }

    static func save(_ baseline: NetworkHealthBaseline) {
        guard let data = try? JSONEncoder().encode(baseline) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

private enum AccountNetworkHealth: Equatable {
    case low(String)
    case medium(String)
    case high(String)

    var title: String {
        switch self {
        case .low: return "适合登录"
        case .medium: return "需要留意"
        case .high: return "不建议登录"
        }
    }

    var reason: String {
        switch self {
        case let .low(reason), let .medium(reason), let .high(reason):
            return reason
        }
    }

    var systemImage: String {
        switch self {
        case .low: return "checkmark.shield"
        case .medium: return "exclamationmark.triangle"
        case .high: return "xmark.octagon"
        }
    }

    var tint: Color {
        switch self {
        case .low: return WidgetPalette.statusSuccess
        case .medium: return WidgetPalette.statusWarning
        case .high: return WidgetPalette.statusDanger
        }
    }
}

private enum IPEnvironmentRisk: Equatable {
    case low
    case medium
    case high

    var title: String {
        switch self {
        case .low: return "环境较稳"
        case .medium: return "需要留意"
        case .high: return "高风险"
        }
    }

    var systemImage: String {
        switch self {
        case .low: return "checkmark.shield"
        case .medium: return "exclamationmark.triangle"
        case .high: return "xmark.octagon"
        }
    }

    var tint: Color {
        switch self {
        case .low: return WidgetPalette.statusSuccess
        case .medium: return WidgetPalette.statusWarning
        case .high: return WidgetPalette.statusDanger
        }
    }
}

private struct IPRiskFlag: Identifiable, Equatable {
    var id: String { title }
    let title: String
    let systemImage: String
    let isActive: Bool
}

private struct IPWhoIsResponse: Decodable {
    let success: Bool?
    let message: String?
    let ip: String?
    let type: String?
    let country: String?
    let region: String?
    let city: String?
    let latitude: Double?
    let longitude: Double?
    let timezone: IPWhoIsTimezone?
    let connection: IPWhoIsConnection?
    let security: IPWhoIsSecurity?
}

private struct PublicIPProbe: Equatable {
    let source: String
    let ip: String
}

private struct PublicIPProbeResponse: Decodable {
    let ip: String
}

private struct IPWhoIsTimezone: Decodable, Equatable {
    let id: String?
}

private struct IPWhoIsConnection: Decodable, Equatable {
    let asn: Int?
    let org: String?
    let isp: String?
    let domain: String?
}

private struct IPWhoIsSecurity: Decodable, Equatable {
    let anonymous: Bool?
    let proxy: Bool?
    let vpn: Bool?
    let tor: Bool?
    let hosting: Bool?
    let abuser: Bool?

    init(
        anonymous: Bool? = nil,
        proxy: Bool? = nil,
        vpn: Bool? = nil,
        tor: Bool? = nil,
        hosting: Bool? = nil,
        abuser: Bool? = nil
    ) {
        self.anonymous = anonymous
        self.proxy = proxy
        self.vpn = vpn
        self.tor = tor
        self.hosting = hosting
        self.abuser = abuser
    }

    init(primary: IPWhoIsSecurity?, riskDTO: IPAPIIsResponse?) {
        self.init(
            anonymous: primary?.anonymous,
            proxy: riskDTO?.isProxy ?? primary?.proxy,
            vpn: riskDTO?.isVPN ?? primary?.vpn,
            tor: riskDTO?.isTor ?? primary?.tor,
            hosting: riskDTO?.isDatacenter ?? primary?.hosting,
            abuser: riskDTO?.isAbuser
        )
    }

    var proxyText: String { boolText(proxy) }
    var vpnText: String { boolText(vpn) }
    var torText: String { boolText(tor) }
    var hostingText: String { boolText(hosting) }
    var abuserText: String { boolText(abuser) }

    private func boolText(_ value: Bool?) -> String {
        guard let value else { return "未知" }
        return value ? "是" : "否"
    }
}

private struct IPAPIIsResponse: Decodable, Equatable {
    let isDatacenter: Bool?
    let isTor: Bool?
    let isProxy: Bool?
    let isVPN: Bool?
    let isAbuser: Bool?
    let datacenter: IPAPIIsDatacenter?
    let company: IPAPIIsCompany?
    let asn: IPAPIIsASN?

    enum CodingKeys: String, CodingKey {
        case isDatacenter = "is_datacenter"
        case isTor = "is_tor"
        case isProxy = "is_proxy"
        case isVPN = "is_vpn"
        case isAbuser = "is_abuser"
        case datacenter
        case company
        case asn
    }
}

private struct IPAPIIsDatacenter: Decodable, Equatable {
    let name: String?
    let domain: String?
    let network: String?

    enum CodingKeys: String, CodingKey {
        case name = "datacenter"
        case domain
        case network
    }

    var displayName: String {
        [name, domain, network].compactMap { value in
            guard let value, !value.isEmpty else { return nil }
            return value
        }.joined(separator: " / ")
    }
}

private struct IPAPIIsCompany: Decodable, Equatable {
    let name: String?
    let domain: String?
    let type: String?
    let network: String?
    let abuserScore: String?

    enum CodingKeys: String, CodingKey {
        case name
        case domain
        case type
        case network
        case abuserScore = "abuser_score"
    }
}

private struct IPAPIIsASN: Decodable, Equatable {
    let asn: Int?
    let descr: String?
    let route: String?
    let abuserScore: String?

    enum CodingKeys: String, CodingKey {
        case asn
        case descr
        case route
        case abuserScore = "abuser_score"
    }
}
