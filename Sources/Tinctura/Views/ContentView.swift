import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
        } detail: {
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .top) {
                    if appState.showCopiedToast {
                        ToastBanner(message: appState.toastMessage)
                            .padding(.top, 12)
                            .zIndex(10)
                    }
                }
                .animation(.spring(response: 0.35), value: appState.showCopiedToast)
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Picker("格式", selection: $appState.preferredFormat) {
                    ForEach(ColorFormat.allCases) { f in
                        Text(f.rawValue).tag(f)
                    }
                }
                .frame(width: 110)

                Button {
                    appState.copyCurrent()
                } label: {
                    Label("复制", systemImage: "doc.on.doc")
                }
                .help("复制当前颜色 (\(appState.preferredFormat.rawValue))")
                .keyboardShortcut("c", modifiers: [.command])

                currentColorChip
            }
        }
    }

    private var sidebar: some View {
        List(selection: $appState.selectedTab) {
            Section("功能") {
                ForEach(AppState.Tab.allCases) { tab in
                    Label(tab.rawValue, systemImage: tab.icon)
                        .tag(tab)
                }
            }

            Section("当前颜色") {
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(appState.currentColor.swiftUIColor)
                        .frame(width: 36, height: 36)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                        )
                    VStack(alignment: .leading, spacing: 2) {
                        Text(appState.currentColor.hex)
                            .font(.system(.caption, design: .monospaced).weight(.semibold))
                        Text(appState.currentColor.hslString)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .padding(.vertical, 4)
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            Text("Tinctura")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity)
                .padding(.bottom, 8)
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch appState.selectedTab {
        case .picker:
            PickerView()
        case .contrast:
            ContrastPreviewView()
        case .analyzer:
            ImageAnalyzerView()
        case .walk:
            ColorWalkView()
        case .history:
            HistoryView()
        }
    }

    private var currentColorChip: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(appState.currentColor.swiftUIColor)
                .frame(width: 16, height: 16)
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.2), lineWidth: 1))
            Text(appState.currentColor.hex)
                .font(.system(.caption, design: .monospaced))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Capsule().fill(Color.primary.opacity(0.06)))
    }
}
