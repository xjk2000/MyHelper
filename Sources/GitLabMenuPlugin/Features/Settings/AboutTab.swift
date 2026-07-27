import SwiftUI

struct AboutTab: View {
    var body: some View {
        VStack {
            VStack(spacing: 12) {
                Image(systemName: "network")
                    .resizable().frame(width: 64, height: 64)
                    .foregroundStyle(.tint)
                Text("GitLabMenu").font(.largeTitle)
                Text("版本 \(BuildInfo.version) (\(BuildInfo.commit))")
                    .foregroundStyle(.secondary)
                Link("项目主页", destination: URL(string: "https://github.com")!)
                    .font(.caption)
            }
            .frame(maxWidth: 360)
            .glassPanel(cornerRadius: 18, padding: EdgeInsets(top: 24, leading: 28, bottom: 24, trailing: 28))
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frostedWindowBackground()
    }
}
