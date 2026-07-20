import AppKit
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    enum Tab: String, CaseIterable, Identifiable {
        case picker = "屏幕取色"
        case contrast = "对比度"
        case analyzer = "图片分析"
        case walk = "颜色漫步"
        case history = "历史"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .picker: return "eyedropper"
            case .contrast: return "circle.lefthalf.filled"
            case .analyzer: return "photo.on.rectangle.angled"
            case .walk: return "waveform.path"
            case .history: return "clock.arrow.circlepath"
            }
        }
    }

    @Published var selectedTab: Tab = .picker
    @Published var currentColor: ColorModel = ColorModel(hex: "#5B8DEF")
    @Published var history: [ColorModel] = []
    @Published var preferredFormat: ColorFormat = .hex
    @Published var showCopiedToast = false
    @Published var toastMessage = ""

    private let historyKey = "SwiftColor.history"
    private let maxHistory = 80

    init() {
        loadHistory()
    }

    func selectColor(_ color: ColorModel, addToHistory: Bool = true) {
        currentColor = color
        if addToHistory {
            pushHistory(color)
        }
    }

    func pushHistory(_ color: ColorModel) {
        if let first = history.first,
           abs(first.red - color.red) < 0.002,
           abs(first.green - color.green) < 0.002,
           abs(first.blue - color.blue) < 0.002 {
            return
        }
        history.insert(color, at: 0)
        if history.count > maxHistory {
            history = Array(history.prefix(maxHistory))
        }
        saveHistory()
    }

    func removeHistory(_ color: ColorModel) {
        history.removeAll { $0.id == color.id }
        saveHistory()
    }

    func clearHistory() {
        history.removeAll()
        saveHistory()
    }

    func copy(_ text: String, label: String? = nil) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        toastMessage = label.map { "已复制 \($0)" } ?? "已复制 \(text)"
        showCopiedToast = true
        Task {
            try? await Task.sleep(nanoseconds: 1_400_000_000)
            showCopiedToast = false
        }
    }

    func copyCurrent(format: ColorFormat? = nil) {
        let f = format ?? preferredFormat
        copy(currentColor.formatted(f), label: f.rawValue)
    }

    private func saveHistory() {
        guard let data = try? JSONEncoder().encode(history) else { return }
        UserDefaults.standard.set(data, forKey: historyKey)
    }

    private func loadHistory() {
        guard let data = UserDefaults.standard.data(forKey: historyKey),
              let items = try? JSONDecoder().decode([ColorModel].self, from: data) else { return }
        history = items
        if let first = items.first {
            currentColor = first
        }
    }
}
