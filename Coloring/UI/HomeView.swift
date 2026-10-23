import SwiftUI

private let columns = [GridItem(.adaptive(minimum: 190, maximum: 260), spacing: 28)]

/// The categories, each as a little pile of pages with its first page on top, in two rows
/// that scroll sideways. The column in the middle is in focus; the further a card is from
/// it, the smaller and blurrier.
struct HomeView: View {
    @ObservedObject var model: AppModel
    @State private var showingSettings = false

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            // The bar stays put: inside the scroll view the gear scrolled away with the cards.
            VStack(spacing: 0) {
                HStack {
                    Spacer()
                    SettingsGear { showingSettings = true }
                }
                .padding([.top, .trailing], 24)
                GeometryReader { geometry in
                    carousel(in: geometry.size)
                }
            }
            if showingSettings {
                SettingsPanel { showingSettings = false }
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: showingSettings)
    }

    private func carousel(in size: CGSize) -> some View {
        // Two rows of card + name fill the height; the tilted back cards and the shadows
        // reach past a card, and the scroll view clips.
        let name: CGFloat = 34, rowGap: CGFloat = 24, inset: CGFloat = 20
        let card = max(120, min(340, (size.height - 2 * inset - rowGap) / 2 - name))
        let pitch = card + 36
        return ScrollView(.horizontal, showsIndicators: false) {
            LazyHGrid(rows: Array(repeating: GridItem(.fixed(card + name), spacing: rowGap), count: 2),
                      spacing: pitch - card) {
                ForEach(model.categories) { category in
                    CategoryCard(category: category, cover: model.covers[category.id],
                                 blurred: model.blurredCovers[category.id], card: card, pitch: pitch,
                                 middle: size.width / 2)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(category.name)
                        .accessibilityIdentifier("category-\(category.id)")
                        .accessibilityAddTraits(.isButton)
                        .onTapGesture { model.show(category) }
                }
            }
            // Half a screen either side, so the first and last columns come to the middle;
            // home opens with the first one there.
            .padding(.horizontal, (size.width - card) / 2)
            .padding(.vertical, inset)
        }
        .coordinateSpace(name: CategoryCard.space)
    }
}

/// A category on home, shrunk, blurred and faded by how far it is from the middle.
private struct CategoryCard: View {
    static let space = "carousel"

    let category: PageCategory
    let cover: UIImage?
    let blurred: UIImage?
    let card: CGFloat
    /// From one column to the next.
    let pitch: CGFloat
    /// The middle of the scroll view, in its own coordinates.
    let middle: CGFloat

    var body: some View {
        GeometryReader { geometry in
            // In columns from the middle.
            let distance = abs(geometry.frame(in: .named(Self.space)).midX - middle) / pitch
            // A little way off center still counts as in focus, so the column in the
            // middle isn't blurred while a scroll comes to rest.
            let blur = min(1, max(0, distance - 0.3))
            VStack(spacing: 12) {
                ZStack {
                    // The card underneath says "there are more inside".
                    RoundedRectangle(cornerRadius: 28, style: .continuous).fill(Theme.card)
                        .shadow(color: Theme.shadow, radius: 6, y: 2)
                        .rotationEffect(.degrees(-5))
                    PageCard(image: cover, blurred: blurred, blur: blur)
                }
                .frame(width: card, height: card)
                Text(category.name)
                    .font(.headline)
                    .foregroundColor(.secondary)
                    .opacity(1 - 0.6 * blur)
            }
            .scaleEffect(1 - 0.2 * min(1, distance / 1.5))
        }
        .frame(width: card)
        // The whole cell, not just the shrunken card: a side card is still easy to hit.
        .contentShape(Rectangle())
    }
}

/// One category's pages, each showing the drawing made on it so far.
struct CategoryView: View {
    @ObservedObject var model: AppModel
    let category: PageCategory
    @State private var confirmingRestart: Page?

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            // Home stays in reach: inside the scroll view it scrolled away with the pages.
            VStack(spacing: 0) {
                HStack {
                    Button(action: model.closeCategory) {
                        ToolTile(isSelected: false, size: 72) {
                            Image(systemName: "house.fill")
                                .font(.system(size: 29, weight: .semibold))
                                .foregroundColor(Theme.selection)
                        }
                    }
                    .buttonStyle(PressableStyle())
                    .accessibilityIdentifier("category-back")
                    .accessibilityLabel("回首頁")
                    Spacer()
                }
                // For the grown-up playing along: which category this is.
                .overlay(
                    Text(category.name)
                        .font(.title2.bold())
                        .foregroundColor(.secondary)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("category-title"))
                .padding([.top, .horizontal], 24)
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 28) {
                        ForEach(category.pages) { page in
                            VStack(spacing: 12) {
                                PageCard(image: model.thumbnails[page.id])
                                Text(page.name)
                                    .font(.headline)
                                    .foregroundColor(.secondary)
                            }
                                // The name too, not just the card: it's part of what a child taps.
                                .contentShape(Rectangle())
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel(page.name)
                                .accessibilityIdentifier("page-\(page.id)")
                                .accessibilityAddTraits(.isButton)
                                .onTapGesture { model.open(page) }
                                // Long, so a child doesn't wipe a page by leaning on it; this
                                // is also how a grown-up resets pages between test sessions.
                                .onLongPressGesture(minimumDuration: 1) { confirmingRestart = page }
                        }
                    }
                    // Top inset: the scroll view clips the cards' shadows.
                    .padding(.top, 16)
                    .padding([.horizontal, .bottom], 36)
                }
            }
            if let page = confirmingRestart {
                RestartConfirmation(
                    image: model.thumbnails[page.id],
                    onConfirm: {
                        confirmingRestart = nil
                        Task { await model.restart(page) }
                    },
                    onCancel: { confirmingRestart = nil })
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: confirmingRestart)
        .task { await model.loadThumbnails() }
    }
}

/// Settings are for grown-ups: a tap does nothing, only a 1 s press opens them, the same
/// guard as restarting a page. Nothing in them can harm a drawing; a setting that could
/// would need a real parental gate.
private struct SettingsGear: View {
    let open: () -> Void

    var body: some View {
        Image(systemName: "gearshape.fill")
            .font(.system(size: 26, weight: .semibold))
            .foregroundColor(.secondary)
            .frame(width: 56, height: 56)
            .background(Circle().fill(Theme.toolFill))
            .contentShape(Circle())
            .onLongPressGesture(minimumDuration: 1, perform: open)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("設定")
            .accessibilityIdentifier("settings")
            .accessibilityAddTraits(.isButton)
            // VoiceOver users activate it directly; a long press is awkward under VoiceOver.
            .accessibilityAction(.default, open)
    }
}

private struct SettingsPanel: View {
    let onClose: () -> Void
    @AppStorage(BrushStyle.paintRunsOutKey) private var paintRunsOut = false

    var body: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea().onTapGesture(perform: onClose)
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("設定").font(.title2.bold())
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 44, height: 44)
                            .background(Circle().fill(Color.gray))
                    }
                    .accessibilityLabel("關閉")
                    .accessibilityIdentifier("settings-close")
                }
                Toggle("顏料會用完", isOn: $paintRunsOut)
                    .font(.title3)
                    .accessibilityIdentifier("setting-paint-runs-out")
                Text("開啟後，油畫、水彩、水墨一筆畫得越長，顏料越少：油畫、水墨會出現乾刷條紋，水彩會變淡。手指放開再畫就重新沾滿。")
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(32)
            .frame(width: 460)
            .background(RoundedRectangle(cornerRadius: 36, style: .continuous).fill(Theme.background))
        }
    }
}

private struct PageCard: View {
    let image: UIImage?
    /// The same picture blurred, shown by `blur`: 0 sharp, 1 fully blurred.
    var blurred: UIImage?
    var blur: CGFloat = 0

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous).fill(Theme.card)
            // Underneath, whole: two half-faded pictures halfway would wash the lines out.
            if let blurred {
                picture(blurred)
            }
            if let image {
                picture(image).opacity(blurred == nil ? 1 : 1 - blur)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .shadow(color: Theme.shadow, radius: 10, y: 4)
        .contentShape(Rectangle())
    }

    private func picture(_ image: UIImage) -> some View {
        Image(uiImage: image)
            .resizable()
            .interpolation(.high)
            .aspectRatio(1, contentMode: .fit)
            // Concentric with the card (28 − 10): square corners showed once a page had color.
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .padding(10)
    }
}

/// Pictures only: the person deciding may not read yet. Restarting a page from home and
/// clearing it on the canvas ask the same question.
struct RestartConfirmation: View {
    let image: UIImage?
    let onConfirm: () -> Void
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.35).ignoresSafeArea().onTapGesture(perform: onCancel)
            VStack(spacing: 28) {
                if let image {
                    Image(uiImage: image).resizable().aspectRatio(1, contentMode: .fit).frame(width: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                }
                HStack(spacing: 48) {
                    Button(action: onCancel) {
                        Image(systemName: "xmark")
                            .font(.system(size: 34, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 88, height: 88)
                            .background(Circle().fill(Color.gray))
                    }
                    .accessibilityIdentifier("restart-cancel")
                    Button(action: onConfirm) {
                        Image(systemName: "trash.fill")
                            .font(.system(size: 34, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 88, height: 88)
                            .background(Circle().fill(Color(red: 0.9, green: 0.22, blue: 0.21)))
                    }
                    .accessibilityIdentifier("restart-confirm")
                }
                .buttonStyle(PressableStyle())
            }
            .padding(36)
            .background(RoundedRectangle(cornerRadius: 36, style: .continuous).fill(Theme.background))
        }
    }
}
