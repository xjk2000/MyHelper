import AppKit
import SwiftUI

struct DeveloperToolWorkbench: View {
    let tool: DeveloperToolID

    @State private var selectedAction: String
    @State private var input: String
    @State private var output = ""
    @State private var errorMessage: String?
    @State private var feedbackMessage: String?
    @State private var regexPattern = #"[\w.+-]+@[\w.-]+\.[A-Za-z]{2,}"#
    @State private var jsonIndent = 2
    @State private var regexCaseInsensitive = false
    @State private var regexMultiline = false
    @State private var uuidCount = 5
    @State private var uuidUppercase = false
    @State private var jsonOutputMode: JSONOutputMode = .source
    @State private var suppressNextJSONAutoFormat = false
    @State private var compareLeftInput: String
    @State private var compareRightInput: String
    @State private var compareResult: JSONComparisonResult?
    @State private var compareErrorMessage: String?

    init(tool: DeveloperToolID) {
        self.tool = tool
        _selectedAction = State(initialValue: tool.actions.first?.id ?? "")
        _input = State(initialValue: tool.defaultInput)
        _compareLeftInput = State(initialValue: tool.defaultInput)
        _compareRightInput = State(initialValue: tool.defaultInput)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            controls
            Divider()

            if tool == .json {
                if selectedAction == "compare" {
                    jsonCompareEditor
                } else {
                    jsonEditor
                }
            } else if tool.needsInputEditor {
                HSplitView {
                    editorPane(
                        title: tool == .regex ? "测试文本" : "输入",
                        text: $input,
                        isOutput: false
                    )
                    .frame(minWidth: 300)

                    editorPane(title: "输出", text: $output, isOutput: true)
                        .frame(minWidth: 300)
                }
            } else {
                editorPane(title: "生成结果", text: $output, isOutput: true)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            if tool == .uuid {
                execute()
            }
        }
        .onChange(of: input) { _, _ in
            guard tool == .json else { return }
            if suppressNextJSONAutoFormat {
                suppressNextJSONAutoFormat = false
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: tool.systemImage)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.tint)
                .frame(width: 38, height: 38)
                .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 3) {
                Text(tool.title)
                    .font(.system(size: 18, weight: .semibold))
                Text(tool.subtitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let feedbackMessage {
                Text(feedbackMessage)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    private var controls: some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                actionPicker

                if tool.supportsIndent {
                    Picker("缩进", selection: $jsonIndent) {
                        Text("2 空格").tag(2)
                        Text("4 空格").tag(4)
                    }
                    .pickerStyle(.menu)
                    .frame(width: 110)
                }

                if tool.supportsUUIDOptions {
                    Stepper("数量 \(uuidCount)", value: $uuidCount, in: 1...100)
                        .frame(width: 120)
                    Toggle("大写", isOn: $uuidUppercase)
                        .toggleStyle(.checkbox)
                }

                if tool.supportsRegexOptions {
                    Toggle("忽略大小写", isOn: $regexCaseInsensitive)
                        .toggleStyle(.checkbox)
                    Toggle("多行", isOn: $regexMultiline)
                        .toggleStyle(.checkbox)
                }

                Spacer(minLength: 8)

                if tool == .timestamp {
                    Button {
                        input = String(Int(Date().timeIntervalSince1970))
                        selectedAction = "to-date"
                    } label: {
                        Image(systemName: "clock")
                            .frame(width: 24, height: 22)
                    }
                    .buttonStyle(.borderless)
                    .help("填入当前时间戳")
                }

                Button(action: execute) {
                    Label(selectedAction == "compare" ? "对比" : "执行", systemImage: selectedAction == "compare" ? "arrow.left.arrow.right" : "play.fill")
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return, modifiers: .command)
            }

            if tool.needsRegexPattern {
                HStack(spacing: 8) {
                    Text("表达式")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                    TextField("正则表达式", text: $regexPattern)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11, design: .monospaced))
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.45))
    }

    private var jsonEditor: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("JSON")
                    .font(.system(size: 11, weight: .semibold))
                Text("\(input.count) 字符")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.tertiary)

                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                        .help(errorMessage)
                }

                Spacer()

                Picker("显示", selection: $jsonOutputMode) {
                    Label("树形", systemImage: "list.bullet.indent").tag(JSONOutputMode.tree)
                    Label("源码", systemImage: "chevron.left.forwardslash.chevron.right").tag(JSONOutputMode.source)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 126)

                Button {
                    pasteInput()
                } label: {
                    Image(systemName: "doc.on.clipboard")
                        .frame(width: 24, height: 22)
                }
                .buttonStyle(.borderless)
                .help("粘贴并格式化")

                Button {
                    copyOutput()
                } label: {
                    Image(systemName: "doc.on.doc")
                        .frame(width: 24, height: 22)
                }
                .buttonStyle(.borderless)
                .disabled(input.isEmpty)
                .help("复制 JSON")

                Button {
                    saveCurrentJSON()
                } label: {
                    Image(systemName: "square.and.arrow.down")
                        .frame(width: 24, height: 22)
                }
                .buttonStyle(.borderless)
                .disabled(input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .help("保存当前 JSON")

                Button {
                    chooseJSONStorageDirectory()
                } label: {
                    Image(systemName: "folder")
                        .frame(width: 24, height: 22)
                }
                .buttonStyle(.borderless)
                .help("选择 JSON 存储目录")

                Button {
                    input = ""
                    output = ""
                    errorMessage = nil
                } label: {
                    Image(systemName: "trash")
                        .frame(width: 24, height: 22)
                }
                .buttonStyle(.borderless)
                .disabled(input.isEmpty)
                .help("清空")
            }
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(.bar)

            if jsonOutputMode == .tree {
                JSONEditableTreeView(
                    jsonText: input,
                    indent: jsonIndent,
                    onChange: { editedJSON in
                        suppressNextJSONAutoFormat = true
                        input = editedJSON
                        output = editedJSON
                        errorMessage = nil
                        showFeedback("JSON 已同步")
                    }
                )
            } else {
                JSONHighlightedTextView(
                    text: $input,
                    onTextChange: { _ in
                        errorMessage = nil
                    },
                    onPasteTextChange: { pastedText in
                        formatJSONAfterPaste(pastedText)
                    }
                )
            }
        }
    }

    private var jsonCompareEditor: some View {
        VStack(spacing: 0) {
            if let compareResult {
                jsonCompareIDEADiffView(compareResult)
            } else {
                if let compareErrorMessage {
                    Label(compareErrorMessage, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.red.opacity(0.07))
                }

                HSplitView {
                    jsonCompareInputPane(
                        title: "左侧基准",
                        text: $compareLeftInput,
                        pasteAction: { formatCompareInputAfterPaste($compareLeftInput, value: $0) }
                    )
                    .frame(minWidth: 360)

                    jsonCompareInputPane(
                        title: "右侧目标",
                        text: $compareRightInput,
                        pasteAction: { formatCompareInputAfterPaste($compareRightInput, value: $0) }
                    )
                    .frame(minWidth: 360)
                }
            }
        }
    }

    private func jsonCompareInputPane(
        title: String,
        text: Binding<String>,
        pasteAction: @escaping (String) -> Void
    ) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                Text("\(text.wrappedValue.count) 字符")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.tertiary)

                Spacer()

                Button {
                    formatCompareInput(text)
                } label: {
                    Image(systemName: "curlybraces")
                        .frame(width: 24, height: 22)
                }
                .buttonStyle(.borderless)
                .disabled(text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .help("按 Key 排序并格式化")

                Button {
                    guard let value = NSPasteboard.general.string(forType: .string) else { return }
                    pasteAction(value)
                } label: {
                    Image(systemName: "doc.on.clipboard")
                        .frame(width: 24, height: 22)
                }
                .buttonStyle(.borderless)
                .help("粘贴并格式化")

                Button {
                    text.wrappedValue = ""
                    compareResult = nil
                    compareErrorMessage = nil
                } label: {
                    Image(systemName: "trash")
                        .frame(width: 24, height: 22)
                }
                .buttonStyle(.borderless)
                .disabled(text.wrappedValue.isEmpty)
                .help("清空")
            }
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(.bar)

            JSONHighlightedTextView(
                text: text,
                onTextChange: { _ in
                    compareResult = nil
                    compareErrorMessage = nil
                },
                onPasteTextChange: { pastedText in
                    pasteAction(pastedText)
                }
            )
        }
    }

    private func jsonCompareIDEADiffView(_ result: JSONComparisonResult) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("排序后 JSON 对比")
                    .font(.system(size: 12, weight: .semibold))

                compareBadge("新增", count: result.summary.added.count, color: .green)
                compareBadge("改动", count: result.summary.changed.count, color: .orange)
                compareBadge("缺少", count: result.summary.removed.count, color: .red)

                Spacer()

                Button {
                    compareResult = nil
                    compareErrorMessage = nil
                } label: {
                    Label("编辑", systemImage: "square.and.pencil")
                }
                .buttonStyle(.borderless)
                .help("返回左右输入框")

                Button {
                    copyCompareDiff()
                } label: {
                    Image(systemName: "doc.on.doc")
                        .frame(width: 24, height: 22)
                }
                .buttonStyle(.borderless)
                .help("复制对比结果")
            }
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(.bar)

            HStack(spacing: 0) {
                compareColumnHeader("左侧基准", count: result.leftSortedText.count)
                Rectangle()
                    .fill(Color(nsColor: .separatorColor).opacity(0.7))
                    .frame(width: 1)
                Text("")
                    .frame(width: 38)
                    .background(Color(nsColor: .controlBackgroundColor).opacity(0.35))
                Rectangle()
                    .fill(Color(nsColor: .separatorColor).opacity(0.7))
                    .frame(width: 1)
                compareColumnHeader("右侧目标", count: result.rightSortedText.count)
            }
            .frame(height: 32)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.45))

            if !result.summary.hasChanges {
                Label("两侧 JSON 排序后完全一致", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.green)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.green.opacity(0.08))
            }

            ScrollView(.vertical) {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(result.pairedRows) { row in
                        comparePairRow(row)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            .background(Color(nsColor: .textBackgroundColor))
        }
    }

    private func compareColumnHeader(_ title: String, count: Int) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
            Text("\(count) 字符")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func comparePairRow(_ row: JSONDiffPairRow) -> some View {
        HStack(spacing: 0) {
            compareSideCell(row.left)
                .frame(maxWidth: .infinity, alignment: .leading)
            Rectangle()
                .fill(Color(nsColor: .separatorColor).opacity(0.45))
                .frame(width: 1)
            compareCenterMarker(row.marker)
            Rectangle()
                .fill(Color(nsColor: .separatorColor).opacity(0.45))
                .frame(width: 1)
            compareSideCell(row.right)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: 24)
    }

    private func compareSideCell(_ line: JSONDiffSideLine) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Text(line.lineNumber.map(String.init) ?? "")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(width: 46, alignment: .trailing)
                .padding(.trailing, 8)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.28))

            Text(line.text.isEmpty ? " " : line.text)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(line.kind == .empty ? .clear : .primary)
                .lineLimit(nil)
                .textSelection(.enabled)
                .padding(.leading, 10)
                .padding(.trailing, 18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 2)
        .background(sideLineBackground(for: line.kind))
    }

    private func compareCenterMarker(_ marker: JSONDiffPairMarker) -> some View {
        ZStack {
            markerBackground(for: marker)
            if marker != .unchanged {
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(markerColor(for: marker).opacity(0.75))
                    .frame(width: 3)
                    .padding(.vertical, 3)
            }
        }
        .frame(width: 38)
    }

    private var jsonCompareDiffPane: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("排序后对比")
                    .font(.system(size: 11, weight: .semibold))

                if let compareResult {
                    compareBadge("新增", count: compareResult.summary.added.count, color: .green)
                    compareBadge("改动", count: compareResult.summary.changed.count, color: .orange)
                    compareBadge("缺少", count: compareResult.summary.removed.count, color: .red)
                }

                Spacer()

                Button {
                    copyCompareDiff()
                } label: {
                    Image(systemName: "doc.on.doc")
                        .frame(width: 24, height: 22)
                }
                .buttonStyle(.borderless)
                .disabled(compareResult == nil)
                .help("复制对比结果")
            }
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(.bar)

            if let compareErrorMessage {
                Label(compareErrorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.red.opacity(0.07))
            }

            if let compareResult {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        compareSummaryView(compareResult.summary)
                        compareLineDiffView(compareResult.rows)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(Color(nsColor: .textBackgroundColor))
            } else {
                ContentUnavailableView(
                    "等待对比",
                    systemImage: "arrow.left.arrow.right",
                    description: Text("左侧放基准 JSON，右侧放目标 JSON，点击对比")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .textBackgroundColor))
            }
        }
    }

    private func compareBadge(_ title: String, count: Int, color: Color) -> some View {
        Text("\(title) \(count)")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
    }

    private func compareSummaryView(_ summary: JSONComparisonSummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if !summary.hasChanges {
                Label("两侧 JSON 排序后完全一致", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.green)
            } else {
                if !summary.added.isEmpty {
                    compareChangeSection(title: "新增", color: .green, changes: summary.added)
                }
                if !summary.changed.isEmpty {
                    compareChangeSection(title: "改动", color: .orange, changes: summary.changed)
                }
                if !summary.removed.isEmpty {
                    compareChangeSection(title: "缺少", color: .red, changes: summary.removed)
                }
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.45), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func compareChangeSection(title: String, color: Color, changes: [JSONPathChange]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("\(title) \(changes.count)")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(color)

            ForEach(changes.prefix(40)) { change in
                VStack(alignment: .leading, spacing: 2) {
                    Text(change.path)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    if let leftValue = change.leftValue, let rightValue = change.rightValue {
                        Text("\(leftValue)  ->  \(rightValue)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    } else if let rightValue = change.rightValue {
                        Text("+ \(rightValue)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    } else if let leftValue = change.leftValue {
                        Text("- \(leftValue)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                .padding(.vertical, 2)
            }

            if changes.count > 40 {
                Text("还有 \(changes.count - 40) 项未展开，复制结果可查看完整列表")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func compareLineDiffView(_ rows: [JSONDiffLine]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(rows) { row in
                HStack(spacing: 0) {
                    Text(row.leftLineNumber.map(String.init) ?? "")
                        .frame(width: 34, alignment: .trailing)
                        .foregroundStyle(.tertiary)
                    Text(row.rightLineNumber.map(String.init) ?? "")
                        .frame(width: 34, alignment: .trailing)
                        .foregroundStyle(.tertiary)
                    Text(diffPrefix(for: row.kind))
                        .frame(width: 20, alignment: .center)
                        .foregroundStyle(diffColor(for: row.kind))
                    Text(row.text.isEmpty ? " " : row.text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .font(.system(size: 11, design: .monospaced))
                .padding(.vertical, 2)
                .padding(.trailing, 8)
                .background(diffBackground(for: row.kind))
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.55), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var actionPicker: some View {
        if tool.actions.count <= 4 {
            Picker("操作", selection: $selectedAction) {
                ForEach(tool.actions) { action in
                    Text(action.title).tag(action.id)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: min(CGFloat(tool.actions.count) * 105, 420))
        } else {
            Picker("操作", selection: $selectedAction) {
                ForEach(tool.actions) { action in
                    Text(action.title).tag(action.id)
                }
            }
            .pickerStyle(.menu)
            .frame(width: 170)
        }
    }

    private func editorPane(
        title: String,
        text: Binding<String>,
        isOutput: Bool
    ) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                Text("\(text.wrappedValue.count) 字符")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.tertiary)

                if isOutput, tool == .json {
                    Picker("显示", selection: $jsonOutputMode) {
                        Label("树形", systemImage: "list.bullet.indent").tag(JSONOutputMode.tree)
                        Label("源码", systemImage: "chevron.left.forwardslash.chevron.right").tag(JSONOutputMode.source)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 126)
                }
                Spacer()

                if isOutput {
                    Button {
                        copyOutput()
                    } label: {
                        Image(systemName: "doc.on.doc")
                            .frame(width: 24, height: 22)
                    }
                    .buttonStyle(.borderless)
                    .disabled(output.isEmpty)
                    .help("复制输出")
                } else {
                    Button {
                        pasteInput()
                    } label: {
                        Image(systemName: "doc.on.clipboard")
                            .frame(width: 24, height: 22)
                    }
                    .buttonStyle(.borderless)
                    .help("粘贴输入")
                }

                Button {
                    text.wrappedValue = ""
                    if isOutput { errorMessage = nil }
                } label: {
                    Image(systemName: "trash")
                        .frame(width: 24, height: 22)
                }
                .buttonStyle(.borderless)
                .disabled(text.wrappedValue.isEmpty)
                .help(isOutput ? "清空输出" : "清空输入")
            }
            .padding(.horizontal, 12)
            .frame(height: 38)
            .background(.bar)

            if isOutput, let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.red.opacity(0.07))
            }

            if isOutput, tool == .json, jsonOutputMode == .tree {
                JSONEditableTreeView(
                    jsonText: text.wrappedValue,
                    indent: jsonIndent,
                    onChange: { editedJSON in
                        text.wrappedValue = editedJSON
                        suppressNextJSONAutoFormat = true
                        input = editedJSON
                        showFeedback("JSON 已同步")
                    }
                )
            } else if isOutput, tool == .json {
                JSONHighlightedTextView(
                    text: text,
                    onTextChange: { editedJSON in
                        input = editedJSON
                        errorMessage = nil
                    },
                    onPasteTextChange: { pastedText in
                        let formatted = DeveloperToolProcessor.formatJSONLenient(pastedText, indent: jsonIndent)
                        text.wrappedValue = formatted
                        input = formatted
                        output = formatted
                    }
                )
            } else {
                TextEditor(text: text)
                    .font(.system(size: 12, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .background(Color(nsColor: .textBackgroundColor))
                    .textSelection(.enabled)
            }
        }
    }

    private func execute() {
        if tool == .json {
            executeJSONAction()
            return
        }

        let request = DeveloperToolRequest(
            tool: tool,
            action: selectedAction,
            input: input,
            regexPattern: regexPattern,
            jsonIndent: jsonIndent,
            regexCaseInsensitive: regexCaseInsensitive,
            regexMultiline: regexMultiline,
            uuidCount: uuidCount,
            uuidUppercase: uuidUppercase
        )

        do {
            output = try DeveloperToolProcessor.process(request)
            errorMessage = nil
            if tool == .json {
                jsonOutputMode = .source
            }
            showFeedback("处理完成")
        } catch {
            output = ""
            errorMessage = error.localizedDescription
        }
    }

    private func copyOutput() {
        let value = tool == .json ? input : output
        guard !value.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(value, forType: .string)
        showFeedback("已复制")
    }

    private func pasteInput() {
        guard let value = NSPasteboard.general.string(forType: .string) else { return }
        input = value
        if tool == .json {
            formatJSONAfterPaste(value)
        } else {
            showFeedback("已粘贴")
        }
    }

    private func formatJSONAfterPaste(_ value: String) {
        let formatted = DeveloperToolProcessor.formatJSONLenient(value, indent: jsonIndent)
        suppressNextJSONAutoFormat = true
        input = formatted
        output = formatted
        errorMessage = DeveloperToolProcessor.isValidJSON(formatted) ? nil : "JSON 仍有语法问题，已按结构做宽松格式化"
        jsonOutputMode = .source
        showFeedback("已粘贴并格式化")
    }

    private func formatCompareInput(_ text: Binding<String>) {
        do {
            text.wrappedValue = try JSONCompareEngine.sortedJSONString(text.wrappedValue, indent: jsonIndent)
            compareResult = nil
            compareErrorMessage = nil
            showFeedback("已排序格式化")
        } catch {
            text.wrappedValue = DeveloperToolProcessor.formatJSONLenient(text.wrappedValue, indent: jsonIndent)
            compareResult = nil
            compareErrorMessage = error.localizedDescription
        }
    }

    private func formatCompareInputAfterPaste(_ text: Binding<String>, value: String) {
        do {
            text.wrappedValue = try JSONCompareEngine.sortedJSONString(value, indent: jsonIndent)
            compareResult = nil
            compareErrorMessage = nil
            showFeedback("已粘贴并排序格式化")
        } catch {
            text.wrappedValue = DeveloperToolProcessor.formatJSONLenient(value, indent: jsonIndent)
            compareResult = nil
            compareErrorMessage = error.localizedDescription
        }
    }

    private func executeJSONCompare() {
        do {
            let result = try JSONCompareEngine.compare(
                left: compareLeftInput,
                right: compareRightInput,
                indent: jsonIndent
            )
            compareLeftInput = result.leftSortedText
            compareRightInput = result.rightSortedText
            compareResult = result
            compareErrorMessage = nil
            showFeedback(result.summary.hasChanges ? "已完成对比" : "两侧一致")
        } catch {
            compareResult = nil
            compareErrorMessage = error.localizedDescription
        }
    }

    private func copyCompareDiff() {
        guard let compareResult else { return }
        let text = compareResult.rows
            .map { row in
                "\(diffPrefix(for: row.kind)) \(row.text)"
            }
            .joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        showFeedback("已复制对比结果")
    }

    private func diffPrefix(for kind: JSONDiffLineKind) -> String {
        switch kind {
        case .unchanged: return " "
        case .added: return "+"
        case .removed: return "-"
        }
    }

    private func diffColor(for kind: JSONDiffLineKind) -> Color {
        switch kind {
        case .unchanged: return .secondary
        case .added: return .green
        case .removed: return .red
        }
    }

    private func diffBackground(for kind: JSONDiffLineKind) -> Color {
        switch kind {
        case .unchanged: return Color.clear
        case .added: return Color.green.opacity(0.12)
        case .removed: return Color.red.opacity(0.12)
        }
    }

    private func sideLineBackground(for kind: JSONDiffSideKind) -> Color {
        switch kind {
        case .unchanged:
            return Color.clear
        case .added:
            return Color.green.opacity(0.14)
        case .removed:
            return Color.red.opacity(0.13)
        case .empty:
            return Color(nsColor: .controlBackgroundColor).opacity(0.18)
        }
    }

    private func markerColor(for marker: JSONDiffPairMarker) -> Color {
        switch marker {
        case .unchanged:
            return .clear
        case .added:
            return .green
        case .removed:
            return .red
        case .changed:
            return .orange
        }
    }

    private func markerBackground(for marker: JSONDiffPairMarker) -> Color {
        switch marker {
        case .unchanged:
            return Color(nsColor: .controlBackgroundColor).opacity(0.18)
        case .added:
            return Color.green.opacity(0.10)
        case .removed:
            return Color.red.opacity(0.10)
        case .changed:
            return Color.orange.opacity(0.10)
        }
    }

    @MainActor
    private func saveCurrentJSON() {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return }

        do {
            guard let fileURL = try DeveloperToolkitStorage.saveCurrentJSON(input) else {
                showFeedback("已取消保存")
                return
            }
            showFeedback("已保存 \(fileURL.lastPathComponent)")
        } catch {
            errorMessage = "保存失败：\(error.localizedDescription)"
        }
    }

    @MainActor
    private func chooseJSONStorageDirectory() {
        guard let directory = DeveloperToolkitStorage.chooseStorageDirectory() else {
            showFeedback("已取消选择")
            return
        }
        showFeedback("存储目录：\(directory.lastPathComponent)")
    }

    private func executeJSONAction() {
        if selectedAction == "compare" {
            executeJSONCompare()
            return
        }

        func request(action: String) -> DeveloperToolRequest {
            DeveloperToolRequest(
                tool: .json,
                action: action,
                input: input,
                regexPattern: regexPattern,
                jsonIndent: jsonIndent,
                regexCaseInsensitive: regexCaseInsensitive,
                regexMultiline: regexMultiline,
                uuidCount: uuidCount,
                uuidUppercase: uuidUppercase
            )
        }

        do {
            switch selectedAction {
            case "minify", "sort":
                let processed = try DeveloperToolProcessor.process(request(action: selectedAction))
                suppressNextJSONAutoFormat = true
                input = processed
                output = processed
                errorMessage = nil
                showFeedback("处理完成")
            default:
                let formatted = DeveloperToolProcessor.formatJSONLenient(input, indent: jsonIndent)
                suppressNextJSONAutoFormat = true
                input = formatted
                output = formatted
                errorMessage = DeveloperToolProcessor.isValidJSON(formatted) ? nil : "JSON 仍有语法问题，已按结构做宽松格式化"
                showFeedback("已格式化")
            }
            jsonOutputMode = .source
        } catch {
            let formatted = DeveloperToolProcessor.formatJSONLenient(input, indent: jsonIndent)
            suppressNextJSONAutoFormat = true
            input = formatted
            output = formatted
            errorMessage = "JSON 仍有语法问题，已按结构做宽松格式化"
        }
    }

    private func showFeedback(_ message: String) {
        withAnimation(.easeOut(duration: 0.15)) {
            feedbackMessage = message
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            if feedbackMessage == message {
                withAnimation(.easeIn(duration: 0.15)) {
                    feedbackMessage = nil
                }
            }
        }
    }
}

private enum JSONOutputMode: String, Hashable {
    case tree
    case source
}
