import SwiftUI

struct CloneProgressSheet: View {
    @Environment(CloneJobStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(store.currentJob?.title ?? "操作进度").font(.headline)
                    Spacer()
                    let s = store.summary
                    Text("成功 \(s.success)  失败 \(s.failed)  跳过 \(s.skipped)")
                        .font(.caption).foregroundStyle(.secondary)
                }

                ProgressView(
                    value: Double(doneCount()),
                    total: Double(max(store.currentJob?.projects.count ?? 1, 1))
                )
            }
            .glassPanel(cornerRadius: 16)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 4) {
                    ForEach(store.currentJob?.projects ?? []) { p in
                        HStack(alignment: .top, spacing: 8) {
                            Text(icon(for: store.progress[p.id]))
                            VStack(alignment: .leading, spacing: 3) {
                                HStack(spacing: 6) {
                                    Text(p.pathWithNamespace).font(.body)
                                    if store.progress[p.id] == .running {
                                        ProgressView()
                                            .controlSize(.small)
                                            .scaleEffect(0.7)
                                    }
                                }
                                if case .failed(_) = store.progress[p.id],
                                   let err = store.errors[p.id] {
                                    Text(err)
                                        .font(.caption)
                                        .foregroundStyle(.red)
                                        .lineLimit(3)
                                }
                                let entries = Array((store.logs[p.id] ?? []).suffix(5))
                                if !entries.isEmpty {
                                    VStack(alignment: .leading, spacing: 1) {
                                        ForEach(Array(entries.enumerated()), id: \.offset) { _, entry in
                                            Text(logLine(entry))
                                                .font(.system(.caption2, design: .monospaced))
                                                .foregroundStyle(entry.stream == .stderr ? .orange : .secondary)
                                                .lineLimit(2)
                                                .textSelection(.enabled)
                                        }
                                    }
                                    .padding(.top, 2)
                                }
                            }
                            Spacer()
                        }
                        .padding(.vertical, 3)
                    }
                }
                .padding(4)
            }
            .frame(minHeight: 200)
            .glassPanel(cornerRadius: 16, padding: EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))

            HStack {
                if store.isRunning {
                    Button(role: .destructive) {
                        store.cancel()
                    } label: {
                        Text(store.isCancelling ? "取消中…" : (store.currentJob?.cancelTitle ?? "取消操作"))
                    }
                    .disabled(store.isCancelling)
                }
                Spacer()
                Button("关闭") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .glassPanel(cornerRadius: 16)
        }
        .padding(16)
        .frame(minWidth: 520, minHeight: 360)
        .frostedWindowBackground()
    }

    private func doneCount() -> Int {
        store.progress.values.reduce(into: 0) { acc, v in
            switch v {
            case .succeeded, .failed, .skipped: acc += 1
            default: break
            }
        }
    }

    private func icon(for state: CloneItemState?) -> String {
        switch state {
        case .succeeded: return "✅"
        case .failed:    return "❌"
        case .skipped:   return "⏭"
        case .running:   return "⏳"
        case .pending, nil: return "•"
        }
    }

    private func logLine(_ entry: GitOutput) -> String {
        let prefix = entry.stream == .stderr ? "err" : "out"
        return "[\(prefix)] \(entry.message)"
    }
}
