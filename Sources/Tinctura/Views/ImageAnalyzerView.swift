import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ImageAnalyzerView: View {
    @EnvironmentObject var appState: AppState
    @State private var image: NSImage?
    @State private var swatches: [ExtractedSwatch] = []
    @State private var average: ColorModel?
    @State private var isAnalyzing = false
    @State private var maxColors = 8.0
    @State private var pickedFromImage: ColorModel?
    @State private var isTargeted = false
    @State private var clickNormalized: CGPoint?

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            leftPanel
                .frame(minWidth: 420, maxWidth: .infinity)
            SplitDivider()
                .padding(.horizontal, 20)
            rightPanel
                .frame(minWidth: 340, idealWidth: 380, maxWidth: 460)
        }
        .padding(20)
    }

    private var leftPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("图片颜色分析")
                        .font(.title2.weight(.bold))
                    Text("拖入或选择图片，提取主色并点击取色")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    openPanel()
                } label: {
                    Label("打开图片", systemImage: "folder")
                }
                .buttonStyle(.borderedProminent)
            }

            imageDropZone
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack {
                Text("提取色数")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Slider(value: $maxColors, in: 3...16, step: 1)
                Text("\(Int(maxColors))")
                    .font(.system(.caption, design: .monospaced))
                    .frame(width: 24)
                Button("重新分析") { reanalyze() }
                    .disabled(image == nil || isAnalyzing)
            }
        }
    }

    private var imageDropZone: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.primary.opacity(isTargeted ? 0.08 : 0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(
                            isTargeted ? Color.accentColor : Color.primary.opacity(0.12),
                            style: StrokeStyle(lineWidth: 2, dash: image == nil ? [8] : [])
                        )
                )

            if let image {
                GeometryReader { geo in
                    let fitted = fittedSize(image.size, in: geo.size)
                    ZStack {
                        Image(nsImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: fitted.width, height: fitted.height)
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onEnded { value in
                                        pickColor(at: value.location, imageSize: fitted, container: geo.size, image: image)
                                    }
                            )

                        if let clickNormalized, let pickedFromImage {
                            let origin = CGPoint(
                                x: (geo.size.width - fitted.width) / 2,
                                y: (geo.size.height - fitted.height) / 2
                            )
                            Circle()
                                .strokeBorder(Color.white, lineWidth: 2)
                                .background(Circle().fill(pickedFromImage.swiftUIColor))
                                .frame(width: 16, height: 16)
                                .position(
                                    x: origin.x + clickNormalized.x * fitted.width,
                                    y: origin.y + (1 - clickNormalized.y) * fitted.height
                                )
                                .shadow(radius: 2)
                        }
                    }
                    .frame(width: geo.size.width, height: geo.size.height)
                }
                .padding(16)
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text("拖放图片到此处")
                        .font(.headline)
                    Text("支持 PNG / JPEG / TIFF / HEIC / WebP")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if isAnalyzing {
                ProgressView("分析中…")
                    .padding(20)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
        .onDrop(of: [.fileURL, .image], isTargeted: $isTargeted) { providers in
            handleDrop(providers)
        }
    }

    private var rightPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let average {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("平均色")
                            .font(.headline)
                        HStack(spacing: 12) {
                            ColorSwatchView(color: average, size: 56, cornerRadius: 12) {
                                appState.selectColor(average)
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text(average.hex)
                                    .font(.system(.title3, design: .monospaced).weight(.semibold))
                                Text(average.rgbString)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Button("设为当前色") {
                                    appState.selectColor(average)
                                }
                                .buttonStyle(.link)
                            }
                        }
                    }
                }

                if let pickedFromImage {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("点击取色")
                            .font(.headline)
                        HStack(spacing: 12) {
                            ColorSwatchView(color: pickedFromImage, size: 48, cornerRadius: 10) {
                                appState.selectColor(pickedFromImage)
                            }
                            VStack(alignment: .leading) {
                                Text(pickedFromImage.hex)
                                    .font(.system(.body, design: .monospaced).weight(.medium))
                                Button("复制并选用") {
                                    appState.selectColor(pickedFromImage)
                                    appState.copyCurrent()
                                }
                                .buttonStyle(.link)
                            }
                        }
                    }
                }

                if !swatches.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("主色板")
                                .font(.headline)
                            Spacer()
                            Button("全部加入历史") {
                                for s in swatches {
                                    appState.pushHistory(s.color)
                                }
                                appState.toastMessage = "已加入 \(swatches.count) 个颜色"
                                appState.showCopiedToast = true
                            }
                            .buttonStyle(.link)
                        }

                        // Proportion bar
                        GeometryReader { geo in
                            HStack(spacing: 0) {
                                ForEach(swatches) { s in
                                    Rectangle()
                                        .fill(s.color.swiftUIColor)
                                        .frame(width: max(4, geo.size.width * s.percentage))
                                        .help("\(s.color.hex) · \(Int(s.percentage * 100))%")
                                }
                            }
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        }
                        .frame(height: 28)

                        ForEach(swatches) { s in
                            swatchRow(s)
                        }
                    }
                } else if image != nil && !isAnalyzing {
                    Text("未能提取颜色")
                        .foregroundStyle(.secondary)
                } else if image == nil {
                    ContentUnavailableView(
                        "等待图片",
                        systemImage: "paintpalette",
                        description: Text("打开或拖入图片后自动分析主色")
                    )
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
                }
            }
            .padding(.trailing, 8)
        }
    }

    private func swatchRow(_ s: ExtractedSwatch) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(s.color.swiftUIColor)
                .frame(width: 40, height: 40)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(s.color.hex)
                    .font(.system(.body, design: .monospaced).weight(.medium))
                Text("\(Int(s.percentage * 100))% · \(s.color.hslString)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                appState.copy(s.color.formatted(appState.preferredFormat))
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.borderless)

            Button {
                appState.selectColor(s.color)
            } label: {
                Image(systemName: "checkmark.circle")
            }
            .buttonStyle(.borderless)
            .help("设为当前色")
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
        .onTapGesture {
            appState.selectColor(s.color)
        }
    }

    // MARK: - Actions

    private func openPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image, .png, .jpeg, .tiff, .heic, .webP]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            loadImage(from: url)
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                var url: URL?
                if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else if let u = item as? URL {
                    url = u
                }
                if let url {
                    Task { @MainActor in loadImage(from: url) }
                }
            }
            return true
        }
        if provider.canLoadObject(ofClass: NSImage.self) {
            _ = provider.loadObject(ofClass: NSImage.self) { obj, _ in
                if let img = obj as? NSImage {
                    Task { @MainActor in setImage(img) }
                }
            }
            return true
        }
        return false
    }

    private func loadImage(from url: URL) {
        guard let img = NSImage(contentsOf: url) else { return }
        setImage(img)
    }

    private func setImage(_ img: NSImage) {
        image = img
        pickedFromImage = nil
        clickNormalized = nil
        reanalyze()
    }

    private func reanalyze() {
        guard let image else { return }
        isAnalyzing = true
        let maxC = Int(maxColors)
        Task.detached(priority: .userInitiated) {
            let palette = ImageColorAnalyzer.extractPalette(from: image, maxColors: maxC)
            let avg = ImageColorAnalyzer.averageColor(from: image)
            await MainActor.run {
                self.swatches = palette
                self.average = avg
                self.isAnalyzing = false
            }
        }
    }

    private func pickColor(at location: CGPoint, imageSize: CGSize, container: CGSize, image: NSImage) {
        let origin = CGPoint(
            x: (container.width - imageSize.width) / 2,
            y: (container.height - imageSize.height) / 2
        )
        let local = CGPoint(x: location.x - origin.x, y: location.y - origin.y)
        guard local.x >= 0, local.y >= 0, local.x <= imageSize.width, local.y <= imageSize.height else { return }
        let nx = local.x / imageSize.width
        // SwiftUI Y grows downward; our helper expects bottom-left normalized for y invert
        let ny = 1 - (local.y / imageSize.height)
        clickNormalized = CGPoint(x: nx, y: ny)
        if let c = ImageColorAnalyzer.color(at: CGPoint(x: nx, y: ny), in: image) {
            pickedFromImage = c
            appState.selectColor(c)
        }
    }

    private func fittedSize(_ imageSize: CGSize, in container: CGSize) -> CGSize {
        let pad: CGFloat = 32
        let maxW = container.width - pad
        let maxH = container.height - pad
        let scale = min(maxW / imageSize.width, maxH / imageSize.height, 1)
        return CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
    }
}
