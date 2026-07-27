import SwiftUI

struct MonitorTab: View {
    @Environment(SettingsStore.self) private var settings
    @State private var pollIntervalSeconds = 60
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Form {
                Stepper("刷新间隔: \(pollIntervalSeconds) 秒",
                        value: $pollIntervalSeconds,
                        in: 30...3600,
                        step: 30)

                HStack {
                    if let error {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                    Spacer()
                    Button("保存刷新间隔") {
                        saveInterval()
                    }
                }
            }
            .frame(height: 86)
            .scrollContentBackground(.hidden)
            .glassPanel(cornerRadius: 16)

            Text("观测项目")
                .font(.headline)

            if settings.config.monitor.targets.isEmpty {
                ContentUnavailableView(
                    "还没有观测项目",
                    systemImage: "waveform.path.ecg",
                    description: Text("在项目列表中点击“观测”添加项目，然后在这里调整分支。")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .glassPanel(cornerRadius: 16)
            } else {
                List {
                    ForEach(settings.config.monitor.targets) { target in
                        MonitorTargetRow(target: target)
                            .listRowBackground(Color.clear)
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
                .glassPanel(cornerRadius: 16, padding: EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))
            }
        }
        .padding(8)
        .frostedWindowBackground()
        .onAppear { pollIntervalSeconds = settings.config.monitor.pollIntervalSeconds }
    }

    private func saveInterval() {
        var draft = settings.config.monitor
        draft.pollIntervalSeconds = pollIntervalSeconds
        do {
            try settings.updateMonitorSettings(draft)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private struct MonitorTargetRow: View {
    @Environment(SettingsStore.self) private var settings
    let target: MonitorTarget
    @State private var watches: [MonitorBranchWatch]
    @State private var error: String?

    init(target: MonitorTarget) {
        self.target = target
        _watches = State(initialValue: target.watches)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(target.pathWithNamespace)
                    .font(.body)
                HStack {
                    instanceLabel
                    Text("项目 ID \(target.projectId)")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            ForEach($watches) { $watch in
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(watch.role.displayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        BranchSelectorEditor(selector: $watch.selector)
                        Toggle("监测运行状态", isOn: $watch.monitorEnabled)
                            .toggleStyle(.checkbox)
                            .font(.caption2)
                    }

                    Button {
                        watches.removeAll { $0.id == watch.id }
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack {
                Button {
                    watches.append(MonitorBranchWatch(selector: .fixed(target.branch), role: .custom))
                } label: {
                    Label("添加其他分支", systemImage: "plus.circle")
                }

                Spacer()

                Button {
                    save()
                } label: {
                    Label(watches.isEmpty ? "保存并取消观测" : "保存", systemImage: "checkmark")
                }

                Button(role: .destructive) {
                    remove()
                } label: {
                    Label("删除项目", systemImage: "trash")
                }
            }

            if let error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .padding(.vertical, 6)
    }

    private var instanceLabel: some View {
        let name = settings.config.instances.first(where: { $0.id == target.instanceId })?.name
        return Text(name ?? "未知实例")
    }

    private func save() {
        var draft = target
        draft.watches = watches
        do {
            try settings.updateMonitorTarget(draft)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func remove() {
        do {
            try settings.removeMonitorTarget(id: target.id)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}
