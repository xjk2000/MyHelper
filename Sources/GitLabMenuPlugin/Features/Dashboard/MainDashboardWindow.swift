import SwiftUI

struct MainDashboardWindow: View {
    @Environment(SettingsStore.self) private var settings
    @State private var selectedTab: DashboardTab = .configure

    enum DashboardTab: Hashable {
        case configure
        case projects
        case clone
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            TabView(selection: $selectedTab) {
                SettingsScene()
                    .tabItem { Label(MainDashboardCopy.configureGitLabTitle, systemImage: "server.rack") }
                    .tag(DashboardTab.configure)

                ProjectListWindow()
                    .tabItem { Label(MainDashboardCopy.projectsTitle, systemImage: "tray.and.arrow.down") }
                    .tag(DashboardTab.projects)

                CloneTab()
                    .tabItem { Label("克隆设置", systemImage: "gearshape.2") }
                    .tag(DashboardTab.clone)
                    .padding(12)
            }
        }
        .frame(minWidth: 920, minHeight: 640)
        .frostedWindowBackground()
        .onAppear {
            selectedTab = settings.config.instances.isEmpty ? .configure : .projects
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "network")
                .font(.title2)
                .foregroundStyle(.tint)
                .frame(width: 32, height: 32)
                .glassPanel(cornerRadius: 10, padding: EdgeInsets(top: 5, leading: 5, bottom: 5, trailing: 5))
            VStack(alignment: .leading, spacing: 2) {
                Text("GitLabMenu")
                    .font(.headline)
                Text("配置 GitLab 基本信息，拉取项目列表，然后批量 clone / pull 到本地。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let instance = currentInstance {
                Label(instance.name, systemImage: "checkmark.circle")
                    .glassStatusPill(tint: .green)
            } else {
                Label("未配置 GitLab", systemImage: "exclamationmark.circle")
                    .glassStatusPill(tint: .orange)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .glassPanel(cornerRadius: 18)
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    private var currentInstance: GitLabInstance? {
        if let id = settings.currentInstanceId,
           let inst = settings.config.instances.first(where: { $0.id == id }) {
            return inst
        }
        return settings.config.instances.first
    }
}

struct FrostedWindowBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    LinearGradient(
                        colors: [
                            Color(nsColor: .windowBackgroundColor),
                            Color.accentColor.opacity(0.08),
                            Color(nsColor: .controlBackgroundColor)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    Rectangle()
                        .fill(.ultraThinMaterial)
                }
                .ignoresSafeArea()
            }
    }
}

struct GlassPanelModifier: ViewModifier {
    var cornerRadius: CGFloat = 14
    var padding: EdgeInsets = EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12)

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.regularMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(.white.opacity(0.22), lineWidth: 1)
                    }
                    .shadow(color: .black.opacity(0.08), radius: 18, y: 8)
            }
    }
}

struct GlassStatusPillModifier: ViewModifier {
    let tint: Color

    func body(content: Content) -> some View {
        content
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background {
                Capsule(style: .continuous)
                    .fill(.thinMaterial)
                    .overlay {
                        Capsule(style: .continuous)
                            .strokeBorder(tint.opacity(0.35), lineWidth: 1)
                    }
            }
    }
}

extension View {
    func frostedWindowBackground() -> some View {
        modifier(FrostedWindowBackground())
    }

    func glassPanel(cornerRadius: CGFloat = 14,
                    padding: EdgeInsets = EdgeInsets(top: 10, leading: 12, bottom: 10, trailing: 12)) -> some View {
        modifier(GlassPanelModifier(cornerRadius: cornerRadius, padding: padding))
    }

    func glassStatusPill(tint: Color) -> some View {
        modifier(GlassStatusPillModifier(tint: tint))
    }
}
