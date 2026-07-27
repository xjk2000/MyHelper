import SwiftUI

struct JSONEditableTreeView: View {
    let jsonText: String
    let indent: Int
    let onChange: (String) -> Void

    @State private var root: EditableJSONNode?
    @State private var loadError: String?
    @State private var lastSerializedText: String
    @State private var expandVersion = 0
    @State private var collapseVersion = 0

    init(jsonText: String, indent: Int, onChange: @escaping (String) -> Void) {
        self.jsonText = jsonText
        self.indent = indent
        self.onChange = onChange
        _root = State(initialValue: try? EditableJSONNode.parse(jsonText))
        _lastSerializedText = State(initialValue: jsonText)
    }

    var body: some View {
        Group {
            if root != nil {
                VStack(spacing: 0) {
                    HStack(spacing: 8) {
                        Button {
                            collapseVersion += 1
                        } label: {
                            Label("全部折叠", systemImage: "chevron.right.2")
                        }
                        .controlSize(.small)

                        Button {
                            expandVersion += 1
                        } label: {
                            Label("全部展开", systemImage: "chevron.down.2")
                        }
                        .controlSize(.small)

                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.bar)

                    ScrollView([.vertical, .horizontal]) {
                        JSONTreeNodeView(
                            node: rootBinding,
                            label: "$",
                            canRename: false,
                            onRename: nil,
                            onDelete: nil,
                            expandVersion: expandVersion,
                            collapseVersion: collapseVersion
                        )
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                    }
                }
            } else {
                ContentUnavailableView(
                    "无法显示 JSON 树",
                    systemImage: "exclamationmark.triangle",
                    description: Text(loadError ?? "当前输出不是合法 JSON")
                )
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
        .onChange(of: jsonText) { _, newValue in
            guard newValue != lastSerializedText else { return }
            load(newValue)
        }
        .onChange(of: root) { _, newRoot in
            guard let newRoot else { return }
            let serialized = newRoot.formattedJSON(indent: indent)
            guard serialized != lastSerializedText else { return }
            lastSerializedText = serialized
            onChange(serialized)
        }
    }

    private var rootBinding: Binding<EditableJSONNode> {
        Binding(
            get: { root ?? EditableJSONNode(value: .null) },
            set: { root = $0 }
        )
    }

    private func load(_ text: String) {
        do {
            root = try EditableJSONNode.parse(text)
            loadError = nil
            lastSerializedText = text
        } catch {
            root = nil
            loadError = error.localizedDescription
            lastSerializedText = text
        }
    }
}

private struct JSONTreeNodeView: View {
    @Binding var node: EditableJSONNode

    let label: String
    let canRename: Bool
    let onRename: ((String) throws -> Void)?
    let onDelete: (() -> Void)?
    let expandVersion: Int
    let collapseVersion: Int

    @State private var isExpanded = true
    @State private var isEditingKey = false
    @State private var isEditingValue = false
    @State private var isAddingChild = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            nodeRow

            if node.value.isContainer, isExpanded {
                childRows
                    .padding(.leading, 22)
                    .overlay(alignment: .leading) {
                        Rectangle()
                            .fill(Color.primary.opacity(0.12))
                            .frame(width: 1)
                            .padding(.leading, 8)
                    }
            }
        }
        .sheet(isPresented: $isEditingKey) {
            JSONTextEditSheet(
                title: "修改 JSON Key",
                fieldLabel: "Key",
                initialText: label,
                multiline: false,
                help: "Key 在同一对象中必须唯一。",
                onSave: { value in try onRename?(value) }
            )
        }
        .sheet(isPresented: $isEditingValue) {
            JSONTextEditSheet(
                title: label == "$" ? "修改根 JSON" : "修改 JSON Value",
                fieldLabel: node.value.isContainer ? "JSON 片段" : "Value",
                initialText: node.compactJSON(),
                multiline: node.value.isContainer || node.compactJSON().count > 80,
                help: node.value.isContainer
                    ? "对象或数组必须输入合法 JSON。"
                    : "支持 JSON 字面量；普通文本会保存为字符串。",
                onSave: { value in
                    node.value = try EditableJSONNode.parseEditedValue(value).value
                }
            )
        }
        .sheet(isPresented: $isAddingChild) {
            JSONAddNodeSheet(
                needsKey: isObject,
                onSave: { key, value in
                    try addChild(key: key, valueText: value)
                }
            )
        }
        .onChange(of: expandVersion) { _, _ in
            isExpanded = true
        }
        .onChange(of: collapseVersion) { _, _ in
            isExpanded = false
        }
    }

    private var nodeRow: some View {
        HStack(spacing: 6) {
            if node.value.isContainer {
                Button {
                    isExpanded.toggle()
                } label: {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .frame(width: 16, height: 18)
                }
                .buttonStyle(.plain)
                .help(isExpanded ? "折叠" : "展开")
            } else {
                Color.clear.frame(width: 16, height: 18)
            }

            Text(label)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(canRename ? Color.red : Color.secondary)
                .lineLimit(1)
                .onTapGesture(count: 2) {
                    if canRename { isEditingKey = true }
                }
                .help(canRename ? "双击修改 Key" : "根节点")

            Text(":")
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(.tertiary)

            Text(node.value.displayValue)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(node.value.displayColor)
                .lineLimit(1)
                .onTapGesture(count: 2) {
                    isEditingValue = true
                }
                .help("双击修改 Value")

            Text(node.value.typeName)
                .font(.system(size: 8, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 4, style: .continuous))

            Spacer(minLength: 8)

            if node.value.isContainer {
                Button {
                    isAddingChild = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .semibold))
                        .frame(width: 22, height: 20)
                }
                .buttonStyle(.plain)
                .help(isObject ? "新增 Key / Value" : "新增数组元素")
            }

            Menu {
                if canRename {
                    Button("修改 Key") { isEditingKey = true }
                }
                Button("修改 Value") { isEditingValue = true }
                if node.value.isContainer {
                    Button(isObject ? "新增 Key / Value" : "新增数组元素") {
                        isAddingChild = true
                    }
                }
                if let onDelete {
                    Divider()
                    Button("删除", role: .destructive, action: onDelete)
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 10, weight: .semibold))
                    .frame(width: 22, height: 20)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("节点操作")
        }
        .padding(.horizontal, 6)
        .frame(minWidth: 420, minHeight: 28, alignment: .leading)
        .contentShape(Rectangle())
        .contextMenu {
            if canRename {
                Button("修改 Key") { isEditingKey = true }
            }
            Button("修改 Value") { isEditingValue = true }
            if node.value.isContainer {
                Button(isObject ? "新增 Key / Value" : "新增数组元素") {
                    isAddingChild = true
                }
            }
            if let onDelete {
                Divider()
                Button("删除", role: .destructive, action: onDelete)
            }
        }
    }

    @ViewBuilder
    private var childRows: some View {
        switch node.value {
        case let .object(members):
            if members.isEmpty {
                emptyContainerRow("空对象")
            } else {
                ForEach(members) { member in
                    JSONTreeNodeView(
                        node: objectChildBinding(id: member.id),
                        label: member.key,
                        canRename: true,
                        onRename: { try renameMember(id: member.id, to: $0) },
                        onDelete: { deleteObjectMember(id: member.id) },
                        expandVersion: expandVersion,
                        collapseVersion: collapseVersion
                    )
                }
            }
        case let .array(items):
            if items.isEmpty {
                emptyContainerRow("空数组")
            } else {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    JSONTreeNodeView(
                        node: arrayChildBinding(id: item.id),
                        label: "[\(index)]",
                        canRename: false,
                        onRename: nil,
                        onDelete: { deleteArrayItem(id: item.id) },
                        expandVersion: expandVersion,
                        collapseVersion: collapseVersion
                    )
                }
            }
        case .string, .number, .bool, .null:
            EmptyView()
        }
    }

    private var isObject: Bool {
        if case .object = node.value { return true }
        return false
    }

    private func objectChildBinding(id: UUID) -> Binding<EditableJSONNode> {
        Binding(
            get: {
                guard case let .object(members) = node.value,
                      let member = members.first(where: { $0.id == id }) else {
                    return EditableJSONNode(id: id, value: .null)
                }
                return member.node
            },
            set: { newValue in
                guard case var .object(members) = node.value,
                      let index = members.firstIndex(where: { $0.id == id }) else { return }
                members[index].node = newValue
                node.value = .object(members)
            }
        )
    }

    private func arrayChildBinding(id: UUID) -> Binding<EditableJSONNode> {
        Binding(
            get: {
                guard case let .array(items) = node.value,
                      let item = items.first(where: { $0.id == id }) else {
                    return EditableJSONNode(id: id, value: .null)
                }
                return item
            },
            set: { newValue in
                guard case var .array(items) = node.value,
                      let index = items.firstIndex(where: { $0.id == id }) else { return }
                items[index] = newValue
                node.value = .array(items)
            }
        )
    }

    private func renameMember(id: UUID, to newKey: String) throws {
        let key = newKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw EditableJSONError.emptyKey }
        guard case var .object(members) = node.value,
              let index = members.firstIndex(where: { $0.id == id }) else { return }
        if members.contains(where: { $0.id != id && $0.key == key }) {
            throw EditableJSONError.duplicateKey(key)
        }
        members[index].key = key
        node.value = .object(members)
    }

    private func deleteObjectMember(id: UUID) {
        guard case var .object(members) = node.value else { return }
        members.removeAll { $0.id == id }
        node.value = .object(members)
    }

    private func deleteArrayItem(id: UUID) {
        guard case var .array(items) = node.value else { return }
        items.removeAll { $0.id == id }
        node.value = .array(items)
    }

    private func addChild(key: String?, valueText: String) throws {
        let newNode = try EditableJSONNode.parseEditedValue(valueText)
        switch node.value {
        case var .object(members):
            let normalizedKey = (key ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalizedKey.isEmpty else { throw EditableJSONError.emptyKey }
            if members.contains(where: { $0.key == normalizedKey }) {
                throw EditableJSONError.duplicateKey(normalizedKey)
            }
            members.append(EditableJSONMember(key: normalizedKey, node: newNode))
            node.value = .object(members)
        case var .array(items):
            items.append(newNode)
            node.value = .array(items)
        case .string, .number, .bool, .null:
            return
        }
        isExpanded = true
    }

    private func emptyContainerRow(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 8)
            .frame(height: 26)
    }
}

private struct JSONTextEditSheet: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let fieldLabel: String
    let multiline: Bool
    let help: String
    let onSave: (String) throws -> Void

    @State private var text: String
    @State private var errorMessage: String?

    init(
        title: String,
        fieldLabel: String,
        initialText: String,
        multiline: Bool,
        help: String,
        onSave: @escaping (String) throws -> Void
    ) {
        self.title = title
        self.fieldLabel = fieldLabel
        self.multiline = multiline
        self.help = help
        self.onSave = onSave
        _text = State(initialValue: initialText)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
            Text(fieldLabel)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            if multiline {
                TextEditor(text: $text)
                    .font(.system(size: 12, design: .monospaced))
                    .frame(minHeight: 150)
                    .padding(6)
                    .background(Color(nsColor: .textBackgroundColor))
                    .overlay(Rectangle().stroke(Color.primary.opacity(0.12)))
            } else {
                TextField(fieldLabel, text: $text)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
            }

            Text(help)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                Button("保存") { save() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(width: 430, height: multiline ? 330 : 220)
    }

    private func save() {
        do {
            try onSave(text)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct JSONAddNodeSheet: View {
    @Environment(\.dismiss) private var dismiss

    let needsKey: Bool
    let onSave: (String?, String) throws -> Void

    @State private var key = ""
    @State private var value = "\"\""
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(needsKey ? "新增 Key / Value" : "新增数组元素")
                .font(.system(size: 16, weight: .semibold))

            if needsKey {
                TextField("Key", text: $key)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
            }

            Text("Value")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
            TextEditor(text: $value)
                .font(.system(size: 12, design: .monospaced))
                .frame(minHeight: 120)
                .padding(6)
                .background(Color(nsColor: .textBackgroundColor))
                .overlay(Rectangle().stroke(Color.primary.opacity(0.12)))

            Text("支持对象、数组、数字、布尔值、null；普通文本保存为字符串。")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                Button("新增") { save() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(width: 440, height: needsKey ? 340 : 300)
    }

    private func save() {
        do {
            try onSave(needsKey ? key : nil, value)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private extension EditableJSONValue {
    var displayColor: Color {
        switch self {
        case .object, .array: return .secondary
        case .string: return .blue
        case .number: return .purple
        case .bool: return .orange
        case .null: return .secondary
        }
    }
}
