import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 270)
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
            // All three controls live in one item so the spacing between them
            // is ours. On macOS 26 we hide the toolbar's shared glass so each
            // control draws its own material.
            if #available(macOS 26.0, *) {
                ToolbarItem(placement: .primaryAction) {
                    toolbarControls
                }
                .sharedBackgroundVisibility(.hidden)
            } else {
                ToolbarItem(placement: .primaryAction) {
                    toolbarControls
                }
            }
        }
    }

    @ViewBuilder
    private var formatPicker: some View {
        if #available(macOS 26.0, *) {
            // A borderless Menu has no bezel of its own, so the glass capsule
            // below is the only background (no "capsule inside a capsule").
            formatMenu
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
                .glassCapsule(interactive: true)
        } else {
            Picker("格式", selection: $appState.preferredFormat) {
                ForEach(ColorFormat.allCases) { f in
                    Text(f.rawValue).tag(f)
                }
            }
            .frame(width: 110)
        }
    }

    private var formatMenu: some View {
        Menu {
            ForEach(ColorFormat.allCases) { f in
                Button {
                    appState.preferredFormat = f
                } label: {
                    if appState.preferredFormat == f {
                        Label(f.rawValue, systemImage: "checkmark")
                    } else {
                        Text(f.rawValue)
                    }
                }
            }
        } label: {
            HStack(spacing: 8) {
                Text(appState.preferredFormat.rawValue)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.secondary)
            }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private var toolbarControls: some View {
        HStack(spacing: 12) {
            formatPicker
            currentColorChip
            copyCurrentButton
        }
    }

    private var copyCurrentButton: some View {
        Button {
            appState.copyCurrent()
        } label: {
            Label("复制", systemImage: "doc.on.doc")
                .labelStyle(.iconOnly)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .glassCapsule(interactive: true)
        .help("复制当前颜色 (\(appState.preferredFormat.rawValue))")
        .keyboardShortcut("c", modifiers: [.command])
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
            Text(appState.currentColor.formatted(appState.preferredFormat))
                .font(.system(.caption, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .glassCapsule(interactive: true)
    }
}
