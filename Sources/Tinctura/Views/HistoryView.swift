import SwiftUI

struct HistoryView: View {
    @EnvironmentObject var appState: AppState
    @State private var search = ""

    private var filtered: [ColorModel] {
        if search.isEmpty { return appState.history }
        let q = search.lowercased()
        return appState.history.filter {
            $0.hex.lowercased().contains(q)
                || $0.rgbString.lowercased().contains(q)
                || $0.name.lowercased().contains(q)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("颜色历史")
                        .font(.title2.weight(.bold))
                    Text("共 \(appState.history.count) 个颜色")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(role: .destructive) {
                    appState.clearHistory()
                } label: {
                    Label("清空", systemImage: "trash")
                }
                .disabled(appState.history.isEmpty)
            }

            TextField("搜索 HEX / RGB…", text: $search)
                .textFieldStyle(.roundedBorder)

            if filtered.isEmpty {
                Spacer()
                ContentUnavailableView(
                    search.isEmpty ? "暂无历史" : "无匹配结果",
                    systemImage: "clock",
                    description: Text(search.isEmpty ? "取色后颜色会出现在这里" : "试试其他关键词")
                )
                Spacer()
            } else {
                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 140), spacing: 14)],
                        spacing: 12
                    ) {
                        ForEach(filtered) { color in
                            historyCard(color)
                        }
                    }
                }
            }
        }
        .padding(20)
    }

    private func historyCard(_ color: ColorModel) -> some View {
        VStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 0)
                .fill(color.swiftUIColor)
                .frame(height: 88)
                .overlay(alignment: .topTrailing) {
                    if color.id == appState.currentColor.id {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(color.contrastingTextColor)
                            .padding(6)
                    }
                }

            VStack(alignment: .leading, spacing: 4) {
                Text(color.hex)
                    .font(.system(.callout, design: .monospaced).weight(.semibold))
                Text(color.rgbString)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
        }
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            appState.selectColor(color, addToHistory: false)
        }
        .contextMenu {
            Button("设为当前色") {
                appState.selectColor(color, addToHistory: false)
            }
            Button("复制 \(appState.preferredFormat.rawValue)") {
                appState.copy(color.formatted(appState.preferredFormat))
            }
            Divider()
            Button("删除", role: .destructive) {
                appState.removeHistory(color)
            }
        }
    }
}
