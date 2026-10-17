import CoreText
import UIKit

struct Stamp: Hashable, Sendable {
    enum Kind: Sendable {
        /// A bundled picture; keeps its own colors.
        case emoji
        /// Text drawn in the selected palette color.
        case kaomoji
    }

    let text: String
    let kind: Kind

    /// An emoji's picture (`make stamps`), named by its code points; kaomoji are text.
    var pictureURL: URL? {
        guard kind == .emoji else { return nil }
        let name = text.unicodeScalars.filter { $0.value != 0xFE0F }.map { String($0.value, radix: 16) }
            .joined(separator: "-")
        return Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "Stamps")
    }
}

enum Stamps {
    /// Picker order, one category per row. Drawn from their pictures (Microsoft Fluent
    /// Emoji, MIT), never as text: the system font would draw Apple emoji, which may not
    /// be shipped inside an app or as stickers (App Review Guidelines 4.5.6, 5.2.5).
    static let emoji: [[String]] = [
        ["🐶", "🐱", "🐭", "🐹", "🐰", "🦊", "🐻", "🐼", "🐨", "🐯", "🦁", "🐮", "🐷", "🐸", "🐵", "🐔",
         "🐧", "🐦", "🐥", "🦆", "🦉", "🐴", "🦄", "🐝", "🐛", "🦋", "🐌", "🐞", "🐢", "🦖", "🐙", "🦀",
         "🐠", "🐟", "🐬", "🐳", "🦈", "🐘", "🦒", "🦓"],
        ["🍎", "🍐", "🍊", "🍋", "🍌", "🍉", "🍇", "🍓", "🍒", "🍑", "🍍", "🥝", "🥥", "🍅", "🥕", "🌽",
         "🥦", "🥑", "🍄", "🥐", "🍞", "🧀", "🥚", "🥞", "🍔", "🍟", "🍕", "🌭", "🍿", "🍙", "🍩", "🍪",
         "🎂", "🧁", "🍰", "🍫", "🍬", "🍭", "🍦", "🍨", "🥛", "🧃"],
        ["🚗", "🚕", "🚙", "🚌", "🚓", "🚑", "🚒", "🚐", "🚚", "🚛", "🚜", "🏎️", "🛵", "🚲", "🛴", "🚂",
         "🚄", "🚇", "🚃", "✈️", "🚁", "🚀", "🛸", "⛵", "🚤", "🚢"],
        ["🌸", "🌷", "🌹", "🌺", "🌻", "🌼", "💐", "🌱", "🌿", "🍀", "🍁", "🍂", "🌳", "🌴", "🌵", "🌈",
         "☀️", "⛅", "☁️", "🌧️", "⛈️", "❄️", "⛄", "🌙", "⭐", "🌟", "✨", "⚡", "🔥", "💧", "🌊", "🌍",
         "🪐"],
        ["🎈", "🎉", "🎁", "🎀", "🧸", "🪀", "🪁", "⚽", "🏀", "🏈", "⚾", "🎾", "🏐", "🎨", "🖍️", "✏️",
         "📚", "🎵", "🎸", "🥁", "🎺", "🎹", "🏠", "🏰", "⛺", "🎡", "🎠", "🎢", "👑", "💎", "🔔", "💡"],
        ["😀", "😃", "😄", "😁", "😆", "😊", "🙂", "😉", "😍", "🥰", "😘", "😋", "😛", "😜", "🤪", "😎",
         "🤩", "🥳", "😮", "😴", "🤗", "🤔", "😢", "😭", "🥺", "👻", "👽", "🤖", "❤️", "🧡", "💛", "💚",
         "💙", "💜", "🤍", "💖", "👍", "👏", "🙌"],
    ]

    /// One list per `emoji` category, shown after its emoji. No characters the system
    /// draws as color emoji (☀ ✈ ✨ ♨): they'd ignore the palette color, and they'd be
    /// Apple emoji. No combining
    /// marks: `isRenderable` can't see whether they stack right.
    static let kaomoji: [[String]] = [
        ["ʕ•ᴥ•ʔ", "(=^･ω･^=)", "ฅ^•ﻌ•^ฅ", "U・ᴥ・U", "∪･ω･∪", "(・(ｴ)・)", "／(･ × ･)＼", "(・θ・)",
         "><((((º>", "(ᵔᴥᵔ)", "(=①ω①=)", "(・⊝・)"],
        ["(っ˘ڡ˘ς)", "(๑´ڡ`๑)", "ლ(´ڡ`ლ)", "(˘ڡ˘)", "(*´﹃｀*)", "(￣～￣)", "(〃＾▽＾〃)", "٩(◕‿◕｡)۶",
         "(*￣▽￣)b"],
        ["ε=ε=┌( >_<)┘", "ε=ε=(ノ≧∇≦)ノ", "ᕕ( ᐛ )ᕗ", "ε=┏(・_・)┛", "ヘ(￣ー￣ヘ)", "(￣^￣)ゞ", "(｀・ω・´)ゞ",
         "ヽ(°〇°)ﾉ", "(ノ°▽°)ノ"],
        ["(✿◠‿◠)", "(◕‿◕✿)", "✿(｡◕ᴗ◕｡)✿", "(❁´◡`❁)", "(☆▽☆)", "☆(ﾉ◕ヮ◕)ﾉ", "★~(◠‿◕✿)", "(*˘︶˘*)",
         "☽(˘ω˘)"],
        ["♪(´▽｀)", "♪～(´ε｀ )", "┏(＾0＾)┛", "┗(＾0＾)┓", "ヽ(⌐■_■)ノ♪", "(∩^o^)⊃━☆", "＼(^o^)／", "ヽ(・∀・)ノ",
         "٩(ˊᗜˋ*)و", "(ﾉ´ヮ`)ﾉ"],
        ["(＾▽＾)", "(◕‿◕)", "(・ω・)", "(￣▽￣)", "(*^ω^*)", "(≧▽≦)", "(｡♥‿♥｡)", "( ˘ ³˘)♥", "(っ´▽`)っ",
         "(〃▽〃)", "(￣o￣) zZ", "(╥﹏╥)", "(°ロ°)!", "(๑˃ᴗ˂)ﻭ"],
    ]

    /// What can be drawn: an emoji whose picture is bundled, a kaomoji the running OS has
    /// every glyph of. A glyph the system fonts lack renders as a tofu box, and kaomoji
    /// lean on scattered Unicode blocks; filtering at runtime is the only check that
    /// holds on an iPadOS 15 device we can't test every glyph on.
    private static let categories: [[Stamp]] = zip(emoji, kaomoji)
        .map { emoji, kaomoji in
            (emoji.map { Stamp(text: $0, kind: .emoji) } + kaomoji.map { Stamp(text: $0, kind: .kaomoji) })
                .filter(isRenderable)
        }
        .filter { !$0.isEmpty }

    /// Every stamp in picker order; a stamp's index here is its identity in the UI.
    static let available: [Stamp] = categories.flatMap { $0 }

    /// Where each category sits in `available`; its first stamp stands for it in the picker.
    static let groups: [Range<Int>] = categories.reduce(into: []) { ranges, category in
        let start = ranges.last?.upperBound ?? 0
        ranges.append(start..<start + category.count)
    }

    /// The emoji at picker size, decoded once for the app's life (~8 MB). The picker isn't
    /// lazy, so it draws every one the moment it opens: decoding 212 PNGs then, on the
    /// main thread, would hold it up. AppModel starts this off the main thread at launch.
    /// 96 px: a picker tile shows 44 pt at 2×.
    static let thumbnails: [Stamp: UIImage] = Dictionary(uniqueKeysWithValues: available.compactMap { stamp in
        stamp.pictureURL
            .flatMap { UIImage(contentsOfFile: $0.path)?.preparingThumbnail(of: CGSize(width: 96, height: 96)) }
            .map { (stamp, $0) }
    })

    static func isRenderable(_ stamp: Stamp) -> Bool {
        if stamp.kind == .emoji { return stamp.pictureURL != nil }
        let base = UIFont.systemFont(ofSize: 40) as CTFont
        for scalar in stamp.text.unicodeScalars {
            // Variation selectors and spaces have no glyph of their own by design.
            if scalar.properties.isVariationSelector || scalar.properties.isWhitespace { continue }
            let string = String(scalar) as CFString
            let font = CTFontCreateForString(base, string, CFRange(location: 0, length: CFStringGetLength(string)))
            if CTFontCopyPostScriptName(font) as String == "LastResort" { return false }
            var units = Array(String(scalar).utf16)
            var glyphs = [CGGlyph](repeating: 0, count: units.count)
            if !CTFontGetGlyphsForCharacters(font, &units, &glyphs, units.count) { return false }
        }
        return true
    }
}
