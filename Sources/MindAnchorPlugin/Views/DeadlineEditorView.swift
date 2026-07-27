import SwiftUI

struct DeadlineEditorView: View {
    let taskId: UUID

    @Binding var hasDeadline: Bool
    @Binding var deadline: Date

    @State private var selectedPreset: DeadlinePreset?
    @State private var panelScale: CGFloat = 1
    @State private var deadlineText = ""
    @State private var inputError: String?
    @State private var isPickerPopoverPresented = false
    @FocusState private var isDeadlineTextFocused: Bool

    private let calendar = Calendar.current

    var body: some View {
        content
            .padding(14)
            .background(panelBackground)
            .scaleEffect(panelScale)
            .animation(.spring(response: 0.42, dampingFraction: 0.72, blendDuration: 0.08), value: hasDeadline)
            .animation(.spring(response: 0.42, dampingFraction: 0.72, blendDuration: 0.08), value: selectedPreset)
            .onAppear {
                selectedPreset = hasDeadline ? matchingPreset(for: deadline) : nil
                deadlineText = DisplayFormatters.preciseDeadline.string(from: deadline)
            }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if hasDeadline {
                expandedControls
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.96, anchor: .top).combined(with: .opacity),
                    removal: .scale(scale: 0.98, anchor: .top).combined(with: .opacity)
                ))
            }
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(deadlineAccent.opacity(hasDeadline ? 0.18 : 0.10))
                Image(systemName: hasDeadline ? "clock.badge.checkmark" : "clock")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(hasDeadline ? deadlineAccent : .secondary)
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 3) {
                Text("截止时间")
                    .font(.callout.weight(.semibold))
                Text(hasDeadline ? deadlineSummary : "未设置，任务不会触发截止提醒")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Toggle("", isOn: $hasDeadline.animation(.spring(response: 0.36, dampingFraction: 0.78)))
                .labelsHidden()
                .toggleStyle(.switch)
                .onChange(of: hasDeadline) { _, enabled in
                    if enabled {
                        normalizeDeadlineIfNeeded()
                    }
                    AppLog.app.info("deadline_editor_toggled platform=macOS taskId=\(taskId.uuidString, privacy: .public) enabled=\(enabled, privacy: .public)")
                }
        }
    }

    private var expandedControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            timeSummaryButton
            presetButtons
        }
    }

    private var timeSummaryButton: some View {
        Button {
            isPickerPopoverPresented.toggle()
        } label: {
            HStack(spacing: 8) {
                Text(DisplayFormatters.preciseDeadline.string(from: deadline))
                    .font(.system(.callout, design: .monospaced).weight(.semibold))
                    .foregroundStyle(.primary)
                Spacer()
                UrgencyBadge(urgency: urgency)
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .popover(isPresented: $isPickerPopoverPresented, arrowEdge: .bottom) {
            popoverEditor
        }
    }

    private var popoverEditor: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("编辑截止时间")
                .font(.headline)

            VStack(alignment: .leading, spacing: 6) {
                Text("精确时间")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)

                HStack(spacing: 8) {
                    TextField("yyyy-MM-dd HH:mm:ss", text: $deadlineText)
                        .font(.system(.callout, design: .monospaced).weight(.medium))
                        .textFieldStyle(.roundedBorder)
                        .focused($isDeadlineTextFocused)
                        .onSubmit { commitDeadlineText() }

                    Button {
                        commitDeadlineText()
                    } label: {
                        Image(systemName: "checkmark")
                            .font(.caption.weight(.bold))
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .help("应用截止时间")
                }

                if let inputError {
                    Text(inputError)
                        .font(.caption2)
                        .foregroundStyle(.red)
                }
            }

            HStack(spacing: 10) {
                DatePicker("日期", selection: $deadline, displayedComponents: .date)
                    .datePickerStyle(.compact)
                DatePicker("时间", selection: $deadline, displayedComponents: .hourAndMinute)
                    .datePickerStyle(.compact)
            }
            .onChange(of: deadline) { _, newValue in
                selectedPreset = matchingPreset(for: newValue)
                syncDeadlineTextIfNeeded()
                inputError = nil
            }
        }
        .padding(16)
        .frame(width: 330)
    }

    private var presetButtons: some View {
        HStack(spacing: 8) {
            ForEach(DeadlinePreset.allCases) { preset in
                DeadlinePresetButton(
                    preset: preset,
                    isSelected: selectedPreset == preset,
                    action: { apply(preset) }
                )
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var panelBackground: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(.regularMaterial)
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(.primary.opacity(0.10), lineWidth: 1)
            }
            .shadow(color: .black.opacity(hasDeadline ? 0.07 : 0.035), radius: hasDeadline ? 10 : 6, x: 0, y: 4)
    }

    private var deadlineAccent: Color {
        switch urgency {
        case .overdue: Color(red: 0.96, green: 0.36, blue: 0.30)
        case .soon: Color(red: 0.91, green: 0.62, blue: 0.22)
        case .normal: Color(red: 0.38, green: 0.55, blue: 0.96)
        }
    }

    private var deadlineSummary: String {
        if deadline < Date() {
            return "已逾期 \(DisplayFormatters.preciseDeadline.string(from: deadline))"
        }

        let relative = RelativeDateTimeFormatter()
        relative.unitsStyle = .full
        return "\(DisplayFormatters.preciseDeadline.string(from: deadline))，\(relative.localizedString(for: deadline, relativeTo: Date()))"
    }

    private var urgency: DeadlineUrgency {
        guard hasDeadline else { return .normal }
        let remaining = deadline.timeIntervalSinceNow
        if remaining < 0 { return .overdue }
        if remaining < 60 * 60 * 24 { return .soon }
        return .normal
    }

    private func apply(_ preset: DeadlinePreset) {
        let resolvedDate = date(for: preset)
        selectedPreset = preset
        deadline = resolvedDate
        deadlineText = DisplayFormatters.preciseDeadline.string(from: resolvedDate)
        inputError = nil

        // 预设时间会覆盖当前选择，因此记录 taskId 和 preset，方便排查“提醒为什么被改到某个时间”。
        AppLog.app.info("deadline_preset_applied platform=macOS taskId=\(taskId.uuidString, privacy: .public) preset=\(preset.rawValue, privacy: .public) deadline=\(resolvedDate.ISO8601Format(), privacy: .public)")

        withAnimation(.interactiveSpring(response: 0.28, dampingFraction: 0.58, blendDuration: 0.06)) {
            panelScale = 0.985
        }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(90))
            withAnimation(.interactiveSpring(response: 0.34, dampingFraction: 0.56, blendDuration: 0.06)) {
                panelScale = 1
            }
        }
    }

    private func normalizeDeadlineIfNeeded() {
        guard deadline.timeIntervalSinceNow < 60 else { return }
        // 启用截止时间时避免默认落在“现在”，否则用户一保存就会变成逾期任务。
        deadline = calendar.date(byAdding: .hour, value: 1, to: Date()) ?? Date().addingTimeInterval(3600)
        deadline = normalizedToSecond(deadline)
        deadlineText = DisplayFormatters.preciseDeadline.string(from: deadline)
        selectedPreset = nil
    }

    private func commitDeadlineText() {
        let trimmed = deadlineText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            inputError = "请输入 yyyy-MM-dd HH:mm:ss"
            return
        }

        guard let parsedDate = DisplayFormatters.preciseDeadline.date(from: trimmed) else {
            inputError = "格式必须是 yyyy-MM-dd HH:mm:ss"
            AppLog.app.info("deadline_text_parse_failed platform=macOS taskId=\(taskId.uuidString, privacy: .public) reason=invalid_format")
            return
        }

        deadline = parsedDate
        selectedPreset = matchingPreset(for: parsedDate)
        inputError = nil
        deadlineText = DisplayFormatters.preciseDeadline.string(from: parsedDate)
        AppLog.app.info("deadline_text_applied platform=macOS taskId=\(taskId.uuidString, privacy: .public) deadline=\(parsedDate.ISO8601Format(), privacy: .public)")
    }

    private func syncDeadlineTextIfNeeded() {
        guard !isDeadlineTextFocused else { return }
        deadlineText = DisplayFormatters.preciseDeadline.string(from: deadline)
    }

    private func matchingPreset(for date: Date) -> DeadlinePreset? {
        DeadlinePreset.allCases.first { preset in
            abs(date.timeIntervalSince(dateForMatching(preset))) < 60
        }
    }

    private func dateForMatching(_ preset: DeadlinePreset) -> Date {
        date(for: preset)
    }

    private func date(for preset: DeadlinePreset) -> Date {
        let now = Date()

        switch preset {
        case .todayEvening:
            let todayEvening = calendar.date(
                bySettingHour: 18,
                minute: 0,
                second: 0,
                of: now
            ) ?? now.addingTimeInterval(3600)
            return normalizedToSecond(todayEvening > now ? todayEvening : now.addingTimeInterval(3600))

        case .tomorrowNoon:
            return normalizedToSecond(dateByAddingDays(1, hour: 12, minute: 0, from: now))

        case .tomorrowEvening:
            return normalizedToSecond(dateByAddingDays(1, hour: 18, minute: 0, from: now))

        case .nextMonday:
            var nextMondayComponents = DateComponents()
            nextMondayComponents.weekday = 2
            nextMondayComponents.hour = 9
            nextMondayComponents.minute = 0
            nextMondayComponents.second = 0

            let nextMonday = calendar.nextDate(
                after: now,
                matching: nextMondayComponents,
                matchingPolicy: .nextTime,
                direction: .forward
            )
            return normalizedToSecond(nextMonday ?? dateByAddingDays(7, hour: 9, minute: 0, from: now))
        }
    }

    private func dateByAddingDays(_ days: Int, hour: Int, minute: Int, from date: Date) -> Date {
        let targetDay = calendar.date(byAdding: .day, value: days, to: date) ?? date.addingTimeInterval(TimeInterval(days * 24 * 3600))
        return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: targetDay) ?? targetDay
    }

    private func normalizedToSecond(_ date: Date) -> Date {
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return calendar.date(from: components) ?? date
    }
}

private enum DeadlinePreset: String, CaseIterable, Identifiable {
    case todayEvening
    case tomorrowNoon
    case tomorrowEvening
    case nextMonday

    var id: String { rawValue }

    var title: String {
        switch self {
        case .todayEvening: "今天下班"
        case .tomorrowNoon: "明天中午"
        case .tomorrowEvening: "明天 18:00"
        case .nextMonday: "下周一"
        }
    }

    var icon: String {
        switch self {
        case .todayEvening: "sunset"
        case .tomorrowNoon: "sun.max"
        case .tomorrowEvening: "moon"
        case .nextMonday: "calendar.badge.clock"
        }
    }
}

private enum DeadlineUrgency {
    case normal
    case soon
    case overdue
}

private struct DeadlinePresetButton: View {
    let preset: DeadlinePreset
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: preset.icon)
                    .font(.caption.weight(.semibold))
                Text(preset.title)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .foregroundStyle(isSelected ? Color.accentColor : .secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.045))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(isSelected ? Color.accentColor.opacity(0.28) : Color.primary.opacity(0.08), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .help(preset.title)
    }
}

private struct UrgencyBadge: View {
    let urgency: DeadlineUrgency

    var body: some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(color.opacity(0.10), in: Capsule(style: .continuous))
    }

    private var title: String {
        switch urgency {
        case .normal: "正常"
        case .soon: "临近"
        case .overdue: "逾期"
        }
    }

    private var color: Color {
        switch urgency {
        case .normal: Color.accentColor
        case .soon: .orange
        case .overdue: .red
        }
    }
}
