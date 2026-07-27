import SwiftUI

struct CloneTab: View {
    @Environment(SettingsStore.self) private var settings
    @State private var draft: CloneSettings = CloneSettings()
    @State private var error: String?

    var body: some View {
        Form {
            Picker("默认模式", selection: $draft.defaultMode) {
                ForEach(CloneMode.allCases) { m in
                    Text(m.displayName).tag(m)
                }
            }
            .pickerStyle(.segmented)

            Stepper("并发数: \(draft.maxConcurrency)",
                    value: $draft.maxConcurrency, in: 1...16)

            Toggle("HTTPS clone 后从 remote URL 擦除 token",
                   isOn: $draft.stripTokenAfterClone)

            HStack {
                if let error { Text(error).foregroundStyle(.red).font(.caption) }
                Spacer()
                Button("保存") {
                    do { try settings.updateCloneSettings(draft); error = nil }
                    catch { self.error = error.localizedDescription }
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(8)
        .scrollContentBackground(.hidden)
        .glassPanel(cornerRadius: 16)
        .padding(8)
        .frostedWindowBackground()
        .onAppear { draft = settings.config.clone }
    }
}
