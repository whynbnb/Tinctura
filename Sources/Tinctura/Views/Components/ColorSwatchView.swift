import SwiftUI

struct ColorSwatchView: View {
    let color: ColorModel
    var size: CGFloat = 44
    var selected: Bool = false
    var showHex: Bool = false
    var cornerRadius: CGFloat = 10
    var action: (() -> Void)?

    var body: some View {
        Button {
            action?()
        } label: {
            VStack(spacing: 4) {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(color.swiftUIColor)
                    .frame(width: size, height: size)
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                            .strokeBorder(
                                selected ? Color.accentColor : Color.primary.opacity(0.12),
                                lineWidth: selected ? 2.5 : 1
                            )
                    )
                    .shadow(color: color.swiftUIColor.opacity(0.35), radius: selected ? 6 : 2, y: 1)

                if showHex {
                    Text(color.hex)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .buttonStyle(.plain)
        .help(color.hex)
    }
}

struct LargeColorPreview: View {
    let color: ColorModel
    var height: CGFloat = 120

    var body: some View {
        ZStack {
            CheckerboardBackground()
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(color.swiftUIColor)

            VStack {
                Spacer()
                HStack {
                    Text(color.hex)
                        .font(.system(.title2, design: .monospaced).weight(.semibold))
                    Spacer()
                    Text(color.rgbString)
                        .font(.system(.caption, design: .monospaced))
                }
                .foregroundStyle(color.contrastingTextColor)
                .padding(14)
                .background(
                    LinearGradient(
                        colors: [.clear, color.swiftUIColor.opacity(0.9)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            }
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .frame(height: height)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
        )
    }
}

struct CheckerboardBackground: View {
    var cell: CGFloat = 8

    var body: some View {
        Canvas { context, size in
            let cols = Int(ceil(size.width / cell))
            let rows = Int(ceil(size.height / cell))
            for row in 0..<rows {
                for col in 0..<cols {
                    let light = (row + col) % 2 == 0
                    let rect = CGRect(
                        x: CGFloat(col) * cell,
                        y: CGFloat(row) * cell,
                        width: cell,
                        height: cell
                    )
                    context.fill(
                        Path(rect),
                        with: .color(light ? Color.gray.opacity(0.15) : Color.gray.opacity(0.28))
                    )
                }
            }
        }
    }
}

struct FormatCopyRow: View {
    @EnvironmentObject var appState: AppState
    let color: ColorModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(ColorFormat.allCases) { format in
                HStack(spacing: 10) {
                    Text(format.rawValue)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 56, alignment: .leading)

                    Text(color.formatted(format))
                        .font(.system(.body, design: .monospaced))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)

                    Spacer(minLength: 0)

                    Button {
                        appState.copy(color.formatted(format), label: format.rawValue)
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                    .help("复制 \(format.rawValue)")
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(0.04))
                )
            }
        }
    }
}

struct ToastBanner: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.callout.weight(.medium))
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .glassCapsule()
            .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
            .transition(.move(edge: .top).combined(with: .opacity))
    }
}
