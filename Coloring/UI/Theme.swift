import SwiftUI

enum Theme {
    static let background = Color(red: 1.0, green: 0.972, blue: 0.925)
    static let card = Color.white
    static let toolFill = Color(red: 0.96, green: 0.95, blue: 0.93)
    static let selection = Color(red: 0.2, green: 0.2, blue: 0.24)
    static let shadow = Color.black.opacity(0.12)
}

/// Squishes on press — the only "it heard me" feedback on an iPad with no haptics.
/// With Reduce Motion it dims instead: still feedback, nothing moves.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Pressable(label: configuration.label, isPressed: configuration.isPressed)
    }

    private struct Pressable: View {
        let label: ButtonStyleConfiguration.Label
        let isPressed: Bool
        @Environment(\.accessibilityReduceMotion) private var reduceMotion

        var body: some View {
            label
                .scaleEffect(isPressed && !reduceMotion ? 0.88 : 1)
                .opacity(isPressed && reduceMotion ? 0.6 : 1)
                .animation(reduceMotion ? nil : .spring(response: 0.2, dampingFraction: 0.6), value: isPressed)
        }
    }
}

/// A rounded tool tile; selected tiles grow and get a dark ring, so selection never
/// depends on telling two colors apart.
struct ToolTile<Content: View>: View {
    let isSelected: Bool
    let size: CGFloat
    /// Wider than tall for kaomoji; square otherwise.
    var width: CGFloat?
    @ViewBuilder var content: Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        content
            .frame(width: width ?? size, height: size)
            .background(RoundedRectangle(cornerRadius: size * 0.28, style: .continuous).fill(Theme.toolFill))
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                    .strokeBorder(Theme.selection, lineWidth: isSelected ? 4 : 0))
            .scaleEffect(isSelected ? 1.08 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.7), value: isSelected)
    }
}
