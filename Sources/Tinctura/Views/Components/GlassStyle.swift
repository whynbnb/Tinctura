import SwiftUI

/// Helpers for adopting the macOS 26 "Liquid Glass" material.
///
/// `glassEffect` is only available on macOS 26+, so these helpers apply the real
/// Liquid Glass material when running there and fall back to a subtle translucent
/// fill on macOS 15 so the layout keeps looking intentional.
extension View {
    /// Applies a Liquid Glass (or fallback) background behind a rounded rectangle.
    @ViewBuilder
    func glassPanel(
        cornerRadius: CGFloat = 12,
        fallbackOpacity: Double = 0.05,
        interactive: Bool = false
    ) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(
                interactive ? .regular.interactive() : .regular,
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
        } else {
            self.background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.primary.opacity(fallbackOpacity))
            )
        }
    }

    /// Applies a Liquid Glass (or fallback) background behind a capsule.
    @ViewBuilder
    func glassCapsule(
        fallbackOpacity: Double = 0.06,
        interactive: Bool = false
    ) -> some View {
        if #available(macOS 26.0, *) {
            self.glassEffect(
                interactive ? .regular.interactive() : .regular,
                in: Capsule()
            )
        } else {
            self.background(Capsule().fill(Color.primary.opacity(fallbackOpacity)))
        }
    }
}

/// A soft vertical divider for two-column layouts.
///
/// Replaces the hard `HSplitView` hairline with a subtle line that fades out at
/// the top and bottom, so adjacent cards don't end up looking double-ruled.
struct SplitDivider: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color.primary.opacity(0.0),
                Color.primary.opacity(0.16),
                Color.primary.opacity(0.16),
                Color.primary.opacity(0.0)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(width: 1)
        .frame(maxHeight: .infinity)
        .padding(.vertical, 6)
        .accessibilityHidden(true)
    }
}
