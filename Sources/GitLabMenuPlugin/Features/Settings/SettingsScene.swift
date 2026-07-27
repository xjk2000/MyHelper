import SwiftUI

struct SettingsScene: View {
    @Environment(SettingsStore.self) private var settings

    var body: some View {
        TabView {
            InstancesTab()
                .tabItem { Label("实例", systemImage: "server.rack") }
            CloneTab()
                .tabItem { Label("克隆", systemImage: "arrow.triangle.2.circlepath") }
            MonitorTab()
                .tabItem { Label("观测", systemImage: "waveform.path.ecg") }
            AboutTab()
                .tabItem { Label("关于", systemImage: "info.circle") }
        }
        .padding(12)
        .frostedWindowBackground()
    }
}
