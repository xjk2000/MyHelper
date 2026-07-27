import SwiftUI

struct DeveloperToolkitRootView: View {
    @State private var selectedTool: DeveloperToolID = .json
    @State private var searchText = ""

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 290)
        } detail: {
            DeveloperToolWorkbench(tool: selectedTool)
                .id(selectedTool)
        }
        .navigationSplitViewStyle(.balanced)
    }

    private var sidebar: some View {
        List(selection: $selectedTool) {
            ForEach(DeveloperToolCategory.allCases) { category in
                let tools = filteredTools(in: category)
                if !tools.isEmpty {
                    Section(category.title) {
                        ForEach(tools) { tool in
                            DeveloperToolSidebarRow(tool: tool)
                                .tag(tool)
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .searchable(text: $searchText, placement: .sidebar, prompt: "搜索工具")
        .safeAreaInset(edge: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Label("研发工具包", systemImage: "hammer.fill")
                    .font(.system(size: 15, weight: .semibold))
                Text("本地处理，不上传输入内容")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(.bar)
        }
    }

    private func filteredTools(in category: DeveloperToolCategory) -> [DeveloperToolID] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return DeveloperToolID.allCases.filter { tool in
            guard tool.category == category else { return false }
            guard !query.isEmpty else { return true }
            return tool.title.localizedCaseInsensitiveContains(query)
                || tool.subtitle.localizedCaseInsensitiveContains(query)
        }
    }
}

private struct DeveloperToolSidebarRow: View {
    let tool: DeveloperToolID

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: tool.systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.tint)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(tool.title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Text(tool.subtitle)
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 3)
    }
}
