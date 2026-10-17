import SwiftUI

struct CanvasScreen: View {
    @ObservedObject var controller: CanvasController
    /// The page as its category showed it, already decoded: shown until the canvas loads.
    let placeholder: UIImage?
    let onClose: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var confirmingClear = false

    private let padding: CGFloat = 12
    private let gap: CGFloat = 8
    /// Fixed: the tools scroll, so adding one doesn't shrink every tile.
    private let tile: CGFloat = 64

    var body: some View {
        ZStack {
            HStack(alignment: .center, spacing: 16) {
                ToolColumn(controller: controller, tile: tile, gap: gap, onClose: onClose)
                    .zIndex(1)
                canvas
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                SideColumn(controller: controller, tile: tile, gap: gap) {
                    controller.panel = nil
                    confirmingClear = true
                }
            }
            .padding(padding)
            if confirmingClear {
                RestartConfirmation(
                    image: nil,
                    onConfirm: {
                        confirmingClear = false
                        controller.clearAll()
                    },
                    onCancel: { confirmingClear = false })
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: confirmingClear)
        .background(Theme.background.ignoresSafeArea())
        .task { await controller.load() }
    }

    private var canvas: some View {
        ZStack {
            ZStack {
                if !controller.isLoaded, let placeholder {
                    Image(uiImage: placeholder)
                        .resizable()
                        // Leaves once the canvas has faded in over it: fading both at once
                        // dips to the white card halfway.
                        .transition(.asymmetric(insertion: .identity,
                                                removal: AnyTransition.opacity.animation(.linear(duration: 0.01).delay(0.2))))
                }
                CanvasSurface(view: controller.view)
                    .opacity(controller.isLoaded ? 1 : 0)
                    .animation(.easeOut(duration: 0.2), value: controller.isLoaded)
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.card)
                .shadow(color: Theme.shadow, radius: 10, y: 4))
            // Each panel opens on the side of the button that called it.
            switch controller.panel {
            case .stamps?:
                StampPicker(controller: controller)
                    .padding(12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .transition(panelTransition(.topLeading))
            case .color?:
                ColorPanel(controller: controller)
                    .padding(12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .transition(panelTransition(.topTrailing))
            case .size?:
                SizePanel(controller: controller)
                    .padding(12)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
                    .transition(panelTransition(.trailing))
            case nil:
                EmptyView()
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .animation(.spring(response: 0.25, dampingFraction: 0.8), value: controller.panel)
    }

    private func panelTransition(_ anchor: UnitPoint) -> AnyTransition {
        reduceMotion ? .opacity : .scale(scale: 0.9, anchor: anchor).combined(with: .opacity)
    }
}

private struct CanvasSurface: UIViewRepresentable {
    let view: CanvasView

    func makeUIView(context: Context) -> CanvasView { view }
    func updateUIView(_ uiView: CanvasView, context: Context) {}
}

private struct ToolColumn: View {
    @ObservedObject var controller: CanvasController
    let tile: CGFloat
    let gap: CGFloat
    let onClose: () -> Void
    /// The brush whose name is showing beside its button.
    @State private var named: BrushKind?

    var body: some View {
        VStack(spacing: gap) {
            Button(action: onClose) {
                ToolTile(isSelected: false, size: tile) {
                    Image(systemName: "house.fill")
                        .font(.system(size: tile * 0.4, weight: .semibold))
                        .foregroundColor(Theme.selection)
                }
            }
            .accessibilityIdentifier("tool-home")
            .accessibilityLabel("返回")
            // Set apart from the tools: 8 pt from the bucket, a child reaching for the
            // bucket left the page instead.
            .padding(.bottom, 30)

            // ⌂ stays put; the tools below it scroll, so another tool doesn't shrink
            // every tile.
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: gap) {
                    toolButton(.bucket, id: "bucket", label: "油漆桶") {
                        BucketIcon(paint: Color(controller.color.uiColor)).padding(tile * 0.1)
                    }
                    ForEach(BrushKind.allCases, id: \.self) { kind in
                        toolButton(.brush(kind), id: kind.rawValue, label: kind.label) {
                            BrushIcon(kind: kind, paint: Color(controller.color.uiColor)).padding(tile * 0.06)
                        }
                        .anchorPreference(key: NamedBrushBounds.self, value: .bounds) { named == kind ? $0 : nil }
                    }
                    toolButton(.stamp, id: "stamp", label: "印章") {
                        StampLabel(stamp: controller.stamp, color: Color(controller.color.uiColor), size: tile)
                    }
                    toolButton(.eraser, id: "eraser", label: "橡皮擦") {
                        EraserIcon().padding(tile * 0.14)
                    }
                }
                // Room for a selected tile's grown size, which the scroll view would clip.
                .padding(6)
            }
            .frame(width: tile + 12)
        }
        .buttonStyle(PressableStyle())
        // Beside its button but outside the scroll view, which would clip it.
        .overlayPreferenceValue(NamedBrushBounds.self) { bounds in
            GeometryReader { geometry in
                if let bounds, let named {
                    let frame = geometry[bounds]
                    Text(named.label)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(Theme.selection))
                        .fixedSize()
                        .frame(height: frame.height)
                        .offset(x: frame.maxX + gap, y: frame.minY)
                        .transition(.opacity)
                        .allowsHitTesting(false)
                        // VoiceOver already reads the button's label.
                        .accessibilityHidden(true)
                }
            }
        }
        .task(id: named) {
            guard named != nil else { return }
            do {
                try await Task.sleep(nanoseconds: 1_500_000_000)
                withAnimation(.easeOut(duration: 0.2)) { named = nil }
            } catch {
                // Cancelled because another brush was tapped; its name stays up.
            }
        }
    }

    private func toolButton<Icon: View>(_ tool: Tool, id: String, label: String,
                                        @ViewBuilder icon: () -> Icon) -> some View {
        Button {
            if tool == .stamp {
                // Tapping the stamp tool always offers the picker: the stamp in use is
                // on the tile, and choosing another is the next thing a child wants.
                controller.toggle(.stamps)
            } else {
                controller.panel = nil
            }
            controller.select(tool)
            // The only words on this screen, for the grown-up: which brush this is.
            if case .brush(let kind) = tool {
                withAnimation(.easeOut(duration: 0.15)) { named = kind }
            }
        } label: {
            ToolTile(isSelected: controller.tool == tool, size: tile, content: icon)
        }
        .accessibilityIdentifier("tool-\(id)")
        .accessibilityLabel(label)
        .accessibilityAddTraits(controller.tool == tool ? .isSelected : [])
    }
}

/// Where the button of the brush being named is.
private struct NamedBrushBounds: PreferenceKey {
    static var defaultValue: Anchor<CGRect>? { nil }

    static func reduce(value: inout Anchor<CGRect>?, nextValue: () -> Anchor<CGRect>?) {
        value = value ?? nextValue()
    }
}

private struct StampLabel: View {
    let stamp: Stamp
    let color: Color
    let size: CGFloat

    var body: some View {
        switch stamp.kind {
        case .emoji:
            // Never Text: the system font would draw an Apple emoji (Stamps.emoji).
            Image(uiImage: Stamps.thumbnails[stamp] ?? UIImage())
                .resizable()
                .frame(width: size * 0.55, height: size * 0.55)
                .accessibilityLabel(Text(stamp.text))
        case .kaomoji:
            Text(stamp.text)
                .font(.system(size: size * 0.22, weight: .bold))
                .foregroundColor(color)
                .lineLimit(1)
                .minimumScaleFactor(0.3)
                .padding(4)
        }
    }
}

/// Colors, sizes, then what to do with the page. Put away off the right edge until a tool
/// is picked; the toggle at the top stays.
private struct SideColumn: View {
    @ObservedObject var controller: CanvasController
    let tile: CGFloat
    let gap: CGFloat
    let onClear: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let dot = tile * 0.9
        VStack(alignment: .trailing, spacing: gap * 2) {
            toggle
            if controller.sideColumnOpen {
                VStack(spacing: 0) {
                    colors(dot: dot)
                    // The buttons sit at the bottom, where a hand learned them.
                    Spacer(minLength: gap * 2)
                    VStack(spacing: gap * 2) {
                        sizes
                        VStack(spacing: gap) {
                            PhotoButton(controller: controller, tile: tile)
                            HStack(spacing: gap) {
                                Button(action: controller.undoLast) {
                                    ToolTile(isSelected: false, size: tile) {
                                        Image(systemName: "arrow.uturn.backward")
                                            .font(.system(size: tile * 0.4, weight: .bold))
                                            .foregroundColor(Theme.selection)
                                    }
                                }
                                .disabled(!controller.canUndo)
                                .opacity(controller.canUndo ? 1 : 0.35)
                                .accessibilityIdentifier("tool-undo")
                                .accessibilityLabel("復原")
                                Button(action: onClear) {
                                    ToolTile(isSelected: false, size: tile) {
                                        Image(systemName: "trash")
                                            .font(.system(size: tile * 0.38, weight: .semibold))
                                            .foregroundColor(Theme.selection)
                                    }
                                }
                                .accessibilityIdentifier("tool-clear")
                                .accessibilityLabel("全部清掉")
                            }
                        }
                    }
                }
                .transition(reduceMotion ? .opacity : .move(edge: .trailing).combined(with: .opacity))
            }
        }
        // As wide as the colors whether or not they're out, so the canvas never moves.
        .frame(width: 3 * dot + 2 * gap, alignment: .trailing)
        .frame(maxHeight: .infinity, alignment: .top)
        .animation(reduceMotion ? .easeInOut(duration: 0.15) : .spring(response: 0.3, dampingFraction: 0.85),
                   value: controller.sideColumnOpen)
        .buttonStyle(PressableStyle())
    }

    private var toggle: some View {
        Button(action: controller.toggleSideColumn) {
            ToolTile(isSelected: false, size: tile) {
                Image(systemName: controller.sideColumnOpen ? "chevron.right" : "chevron.left")
                    .font(.system(size: tile * 0.34, weight: .bold))
                    .foregroundColor(Theme.selection)
            }
        }
        .accessibilityIdentifier("side-toggle")
        .accessibilityLabel("顏色與大小")
        .accessibilityValue(controller.sideColumnOpen ? "open" : "closed")
    }

    private func colors(dot: CGFloat) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(dot), spacing: gap), count: 3), spacing: gap) {
            ForEach(Palette.colors.indices, id: \.self) { index in
                Button {
                    controller.colorIndex = index
                    controller.panel = nil
                } label: {
                    ColorDot(color: Palette.colors[index], isSelected: controller.colorIndex == index, size: dot)
                }
                .accessibilityIdentifier("color-\(index)")
                .accessibilityLabel(Palette.colors[index].hex)
            }
            Button(action: controller.chooseCustomColor) {
                ColorDot(color: controller.customColor.rgba, isSelected: controller.colorIndex == nil, size: dot,
                         isCustom: true)
            }
            .accessibilityIdentifier("color-custom")
            .accessibilityLabel("自訂顏色")
            .accessibilityValue(controller.customColor.rgba.hex)
        }
    }

    private var sizes: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(tile), spacing: gap), count: 2), spacing: gap) {
            ForEach(BrushSize.allCases, id: \.self) { size in
                Button {
                    controller.size = size
                    controller.panel = nil
                } label: {
                    ToolTile(isSelected: controller.size == size, size: tile) {
                        sizeDot([0.18, 0.36, 0.62][size.rawValue])
                    }
                }
                .accessibilityIdentifier("size-\(size.rawValue)")
            }
            Button(action: controller.chooseCustomSize) {
                ToolTile(isSelected: controller.size == nil, size: tile) {
                    ZStack {
                        sizeDot(customFraction)
                        Image(systemName: "slider.horizontal.3")
                            .font(.system(size: tile * 0.2, weight: .bold))
                            .foregroundColor(Theme.selection)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                            .padding(tile * 0.1)
                    }
                }
            }
            .accessibilityIdentifier("size-custom")
            .accessibilityLabel("自訂大小")
        }
    }

    private func sizeDot(_ fraction: CGFloat) -> some View {
        Circle()
            .fill(Color(controller.color == .white ? UIColor.lightGray : controller.color.uiColor))
            .frame(width: tile * fraction, height: tile * fraction)
    }

    /// The custom size on the same visual scale as S / M / L (24 / 48 / 96 px).
    private var customFraction: CGFloat {
        let pixels = BrushSize.canvasPixels(custom: controller.customSize)
        return min(0.8, max(0.1, 0.18 + 0.22 * CGFloat(log2(pixels / 24))))
    }
}

private struct PhotoButton: View {
    @ObservedObject var controller: CanvasController
    let tile: CGFloat

    var body: some View {
        Button {
            Task { await controller.saveToPhotos() }
        } label: {
            ToolTile(isSelected: false, size: tile) {
                switch controller.photoSave {
                case .ready:
                    Image(systemName: "photo.fill")
                        .font(.system(size: tile * 0.36, weight: .semibold))
                        .foregroundColor(Theme.selection)
                        .overlay(
                            Image(systemName: "arrow.down.circle.fill")
                                .font(.system(size: tile * 0.24, weight: .bold))
                                .foregroundColor(Color(red: 0.12, green: 0.53, blue: 0.9))
                                .background(Circle().fill(Color.white))
                                .offset(x: tile * 0.17, y: tile * 0.15))
                case .saving:
                    ProgressView()
                case .saved:
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: tile * 0.44, weight: .bold))
                        .foregroundColor(Color(red: 0.26, green: 0.63, blue: 0.28))
                case .denied:
                    // Only a grown-up can fix this, in Settings; the child just sees it didn't work.
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: tile * 0.38, weight: .bold))
                        .foregroundColor(Color(red: 0.98, green: 0.55, blue: 0.0))
                }
            }
        }
        // Saved and unchanged since: another copy would only fill up the family's photos.
        .disabled(controller.photoSave == .saving || controller.photoSave == .saved)
        .accessibilityIdentifier("tool-save-photo")
        .accessibilityLabel("存到相簿")
        .accessibilityValue(controller.photoSave == .saved ? "saved" : controller.photoSave == .denied ? "denied" : "")
    }
}

private struct ColorDot: View {
    let color: RGBA
    let isSelected: Bool
    let size: CGFloat
    /// The child's own color: ringed with a rainbow, so it reads as "any color".
    var isCustom = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private static let rainbow = Gradient(colors: (0...6).map {
        Color(hue: Double($0) / 6, saturation: 0.85, brightness: 0.95)
    })

    var body: some View {
        Circle()
            .fill(Color(color.uiColor))
            .overlay(Circle().strokeBorder(Color.black.opacity(0.12), lineWidth: 1))
            .overlay(Circle().strokeBorder(AngularGradient(gradient: Self.rainbow, center: .center),
                                           lineWidth: isCustom ? size * 0.13 : 0))
            .padding(isSelected ? 5 : 0)
            .overlay(Circle().strokeBorder(Theme.selection, lineWidth: isSelected ? 4 : 0))
            .frame(width: size, height: size)
            .scaleEffect(isSelected ? 1.08 : 1)
            .animation(reduceMotion ? nil : .spring(response: 0.25, dampingFraction: 0.7), value: isSelected)
    }
}

private struct StampPicker: View {
    @ObservedObject var controller: CanvasController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollViewReader { scroller in
            VStack(spacing: 0) {
                // Shortcuts, not tabs: every category stays in the one list below, so
                // nothing is ever hidden behind a page a child has to find again.
                HStack(spacing: 16) {
                    ForEach(Stamps.groups.indices, id: \.self) { group in
                        Button {
                            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.3)) {
                                scroller.scrollTo("group-\(group)", anchor: .top)
                            }
                        } label: {
                            ToolTile(isSelected: false, size: 60) {
                                StampLabel(stamp: Stamps.available[Stamps.groups[group].lowerBound],
                                           color: Color(controller.color.uiColor), size: 60)
                            }
                        }
                        .accessibilityIdentifier("stamp-group-\(group)")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 16)
                ScrollView {
                    // Lazy: building all ~230 tiles took 0.55 s on the mini 4 at every open.
                    // A shortcut still lands on its category, since every row is one tile
                    // tall and a lazy stack places rows it hasn't built by that height.
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(Stamps.groups.indices, id: \.self) { group in
                            Capsule().fill(Theme.shadow).frame(height: 3).id("group-\(group)")
                            ForEach(rows(of: Stamps.groups[group]), id: \.self) { row in
                                HStack(spacing: 10) {
                                    ForEach(row, id: \.self) { stampButton($0) }
                                }
                                .id(row)
                            }
                        }
                    }
                    .padding([.horizontal, .bottom], 16)
                }
                .accessibilityIdentifier("stamp-list")
            }
            .onAppear {
                // By row: a tile the lazy stack hasn't built has no id to scroll to.
                if let selected = Stamps.available.firstIndex(of: controller.stamp),
                   let row = Stamps.groups.flatMap(rows(of:)).first(where: { $0.contains(selected) }) {
                    scroller.scrollTo(row, anchor: .center)
                }
            }
        }
        .frame(width: 5 * 80 + 4 * 10 + 32)
        .frame(maxHeight: 560)
        .panelCard()
        .buttonStyle(PressableStyle())
    }

    /// A category's emoji five to a row, then its kaomoji three to a (same-width) row.
    private func rows(of group: Range<Int>) -> [Range<Int>] {
        let split = group.first { Stamps.available[$0].kind == .kaomoji } ?? group.upperBound
        func chunks(_ range: Range<Int>, by n: Int) -> [Range<Int>] {
            stride(from: range.lowerBound, to: range.upperBound, by: n).map { $0..<min($0 + n, range.upperBound) }
        }
        return chunks(group.lowerBound..<split, by: 5) + chunks(split..<group.upperBound, by: 3)
    }

    private func stampButton(_ index: Int) -> some View {
        let stamp = Stamps.available[index]
        return Button {
            controller.stamp = stamp
            controller.select(.stamp)
            controller.panel = nil
        } label: {
            ToolTile(isSelected: controller.stamp == stamp, size: 80, width: stamp.kind == .emoji ? 80 : 140) {
                StampLabel(stamp: stamp, color: Color(controller.color.uiColor), size: 80)
            }
        }
        .accessibilityIdentifier("stamp-\(index)")
    }
}

/// Hue and pale ↔ dark for the child's own color.
private struct ColorPanel: View {
    @ObservedObject var controller: CanvasController

    var body: some View {
        let custom = controller.customColor
        VStack(spacing: 22) {
            Circle()
                .fill(Color(custom.rgba.uiColor))
                .overlay(Circle().strokeBorder(Color.black.opacity(0.12), lineWidth: 1))
                .frame(width: 76, height: 76)
            BigSlider(value: $controller.customColor.hue, knob: Color(custom.rgba.uiColor), id: "custom-hue",
                      label: "顏色") {
                track(stride(from: 0.0, through: 1.0, by: 1.0 / 12).map { swatch(hue: $0, shade: custom.shade) })
            }
            BigSlider(value: $controller.customColor.shade, knob: Color(custom.rgba.uiColor), id: "custom-shade",
                      label: "深淺") {
                track([0, 0.25, 0.5, 0.75, 1].map { swatch(hue: custom.hue, shade: $0) })
            }
        }
        .padding(24)
        .frame(width: 380)
        .panelCard()
    }

    private func swatch(hue: Double, shade: Double) -> Color {
        Color(CustomColor(hue: hue, shade: shade).rgba.uiColor)
    }

    private func track(_ colors: [Color]) -> some View {
        Capsule()
            .fill(LinearGradient(gradient: Gradient(colors: colors), startPoint: .leading, endPoint: .trailing))
            .overlay(Capsule().strokeBorder(Color.black.opacity(0.1), lineWidth: 1))
    }
}

/// One slider for the child's own size, previewed at its real size on the canvas.
private struct SizePanel: View {
    @ObservedObject var controller: CanvasController

    var body: some View {
        let diameter = CGFloat(controller.strokeSize) * controller.view.bounds.width / CGFloat(CanvasSpec.size)
        VStack(spacing: 22) {
            ZStack {
                if controller.tool == .stamp, let url = controller.stamp.pictureURL {
                    // Full size, not the thumbnail: this preview grows past 96 px. The
                    // picture fills 200 of the tip's 256 px (RenderContext.stampTip).
                    Image(uiImage: UIImage(contentsOfFile: url.path) ?? UIImage())
                        .resizable()
                        .frame(width: diameter * 200 / 256, height: diameter * 200 / 256)
                } else if controller.tool == .stamp {
                    Text(controller.stamp.text)
                        .font(.system(size: diameter * 0.5, weight: .bold))
                        .foregroundColor(Color(controller.color.uiColor))
                        .lineLimit(1)
                        .fixedSize()
                } else {
                    Circle()
                        .fill(Color(controller.color == .white ? UIColor.lightGray : controller.color.uiColor))
                        .frame(width: diameter, height: diameter)
                }
            }
            .frame(width: 140, height: 140)
            BigSlider(value: Binding(get: { Double(controller.customSize) },
                                     set: { controller.customSize = Float($0) }),
                      knob: Theme.selection, id: "custom-size", label: "大小") {
                Wedge().fill(Color(white: 0.82))
            }
        }
        .padding(24)
        .frame(width: 380)
        .panelCard()
    }
}

/// A slider for a small hand: a fat track, a big knob, and a touch anywhere on the track
/// jumps there (no aiming at the knob first).
private struct BigSlider<Track: View>: View {
    @Binding var value: Double
    let knob: Color
    let id: String
    let label: String
    @ViewBuilder var track: Track

    private let knobSize: CGFloat = 52

    var body: some View {
        GeometryReader { geometry in
            let travel = max(1, geometry.size.width - knobSize)
            ZStack(alignment: .leading) {
                // Inset by half a knob, so what's under the knob's center is the value.
                track
                    .frame(height: 34)
                    .padding(.horizontal, knobSize / 2)
                Circle()
                    .fill(knob)
                    .overlay(Circle().strokeBorder(Color.white, lineWidth: 5))
                    .shadow(color: Theme.shadow, radius: 4, y: 2)
                    .frame(width: knobSize, height: knobSize)
                    .offset(x: CGFloat(value) * travel)
            }
            .frame(height: knobSize)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                value = min(1, max(0, Double((drag.location.x - knobSize / 2) / travel)))
            })
        }
        .frame(height: knobSize)
        .accessibilityElement()
        .accessibilityIdentifier(id)
        .accessibilityLabel(label)
        .accessibilityValue("\(Int((value * 100).rounded()))%")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = min(1, value + 0.1)
            case .decrement: value = max(0, value - 0.1)
            @unknown default: break
            }
        }
    }
}

/// Thin to thick: the size track draws what it does.
private struct Wedge: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY - 2))
        path.addLine(to: CGPoint(x: rect.maxX - rect.height / 2, y: rect.minY))
        path.addArc(center: CGPoint(x: rect.maxX - rect.height / 2, y: rect.midY), radius: rect.height / 2,
                    startAngle: .degrees(-90), endAngle: .degrees(90), clockwise: false)
        path.addLine(to: CGPoint(x: rect.minX, y: rect.midY + 2))
        path.closeSubpath()
        return path
    }
}

private extension View {
    func panelCard() -> some View {
        background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(Theme.card)
            .shadow(color: Theme.shadow, radius: 16, y: 6))
    }
}

private extension BrushKind {
    var label: String {
        switch self {
        case .crayon: "蠟筆"
        case .marker: "麥克筆"
        case .watercolor: "水彩"
        case .oil: "油畫"
        case .ink: "水墨"
        case .airbrush: "噴槍"
        case .rainbow: "彩虹筆"
        case .glitter: "亮粉"
        case .stars: "星星筆"
        case .puffy: "立體顏料"
        case .chalk: "粉筆"
        case .pencil: "色鉛筆"
        }
    }
}
