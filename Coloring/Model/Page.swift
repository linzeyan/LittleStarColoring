import CryptoKit
import Foundation

/// One coloring page as built by tools/build_pages.py into the bundle's Pages folder.
struct Page: Identifiable, Hashable, Sendable {
    /// The folder name, e.g. "02-rocket": unique across categories, and the key its
    /// artwork is saved under. Its sort order is the order within a category.
    let id: String
    let directory: URL

    var lineArtURL: URL { directory.appendingPathComponent("lineart.png") }
    var regionsURL: URL { directory.appendingPathComponent("regions.png") }
    var thumbnailURL: URL { directory.appendingPathComponent("thumb.png") }

    /// Which drawing of the page this is: a hash of its region map, which every redraw
    /// changes. Artwork remembers it, because fills are keyed by region IDs and a redrawn
    /// page numbers its regions differently.
    var drawing: String {
        guard let data = try? Data(contentsOf: regionsURL) else { return "" }
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    /// Under the page's card: for the grown-up playing along and a child who reads.
    var name: String { Self.names[String(id.drop { $0 != "-" }.dropFirst())] ?? id }

    static let names = [
        "car": "汽車", "bus": "公車", "train": "火車", "airplane": "飛機", "helicopter": "直升機",
        "rocket": "火箭", "sailboat": "帆船", "fire-truck": "消防車", "excavator": "挖土機",
        "hot-air-balloon": "熱氣球", "tractor": "拖拉機", "submarine": "潛水艇",
        "cow": "乳牛", "pig": "小豬", "sheep": "綿羊", "hen": "母雞", "chick": "小雞", "duck": "鴨子",
        "rabbit": "兔子", "dog": "小狗", "cat": "小貓", "goat": "山羊", "mouse": "老鼠", "donkey": "驢子",
        "lion": "獅子", "elephant": "大象", "giraffe": "長頸鹿", "zebra": "斑馬", "monkey": "猴子",
        "tiger": "老虎", "bear": "熊", "hippo": "河馬", "panda": "熊貓", "koala": "無尾熊",
        "kangaroo": "袋鼠", "rhino": "犀牛",
        "fish": "小魚", "whale": "鯨魚", "dolphin": "海豚", "octopus": "章魚", "crab": "螃蟹",
        "sea-turtle": "海龜", "seahorse": "海馬", "shark": "鯊魚", "lobster": "龍蝦",
        "clownfish": "小丑魚", "jellyfish": "水母", "seal": "海豹", "scallop": "扇貝",
        "bird": "小鳥", "penguin": "企鵝", "owl": "貓頭鷹", "peacock": "孔雀", "flamingo": "紅鶴",
        "toucan": "巨嘴鳥", "ostrich": "鴕鳥", "woodpecker": "啄木鳥", "parrot": "鸚鵡", "swan": "天鵝",
        "pelican": "鵜鶘",
        "butterfly": "蝴蝶", "bee": "蜜蜂", "snail": "蝸牛", "caterpillar": "毛毛蟲", "ant": "螞蟻",
        "dragonfly": "蜻蜓", "grasshopper": "蚱蜢", "spider": "蜘蛛", "beetle": "獨角仙",
        "mantis": "螳螂", "ladybug": "瓢蟲",
        "t-rex": "暴龍", "triceratops": "三角龍", "stegosaurus": "劍龍", "brachiosaurus": "腕龍",
        "pterodactyl": "翼龍", "ankylosaurus": "甲龍", "dino-egg": "恐龍蛋", "spinosaurus": "棘龍",
        "parasaurolophus": "副櫛龍", "plesiosaur": "蛇頸龍",
        "flower": "花", "sunflower": "向日葵", "tulip": "鬱金香", "rose": "玫瑰", "tree": "大樹",
        "mushroom": "香菇", "potted-plant": "盆栽", "palm-tree": "椰子樹", "pine-tree": "松樹",
        "cactus": "仙人掌",
        "apple": "蘋果", "strawberry": "草莓", "watermelon": "西瓜", "grapes": "葡萄",
        "pineapple": "鳳梨", "cherry": "櫻桃", "pear": "梨子", "orange": "橘子", "banana": "香蕉",
        "lemon": "檸檬",
        "carrot": "胡蘿蔔", "corn": "玉米", "pumpkin": "南瓜", "eggplant": "茄子", "tomato": "番茄",
        "broccoli": "花椰菜", "bell-pepper": "甜椒", "pea-pod": "豌豆", "onion": "洋蔥",
        "daikon": "白蘿蔔", "bamboo-shoot": "竹筍",
        "ice-cream": "冰淇淋", "cake": "蛋糕", "cupcake": "杯子蛋糕", "donut": "甜甜圈",
        "pizza": "披薩", "hamburger": "漢堡", "lollipop": "棒棒糖", "fries": "薯條",
        "sandwich": "三明治", "pudding": "布丁", "popsicle": "冰棒",
        "house": "房子", "castle": "城堡", "school": "學校", "lighthouse": "燈塔", "barn": "穀倉",
        "igloo": "冰屋", "tent": "帳篷", "windmill": "風車", "treehouse": "樹屋", "shop": "商店",
        "skyscraper": "摩天大樓",
        "sun": "太陽", "rainbow": "彩虹", "umbrella": "雨傘", "snowman": "雪人", "planet": "土星",
        "lightning": "閃電", "moon": "月亮", "cloud": "雲", "kite": "風箏", "earth": "地球",
        "unicorn": "獨角獸", "dragon": "噴火龍", "phoenix": "鳳凰", "pegasus": "飛馬",
        "griffin": "獅鷲", "qilin": "麒麟", "nine-tailed-fox": "九尾狐", "baize": "白澤",
        "chinese-dragon": "龍", "cerberus": "地獄三頭犬",
        "zodiac-rat": "鼠", "zodiac-ox": "牛", "zodiac-tiger": "虎", "zodiac-rabbit": "兔",
        "zodiac-dragon": "龍", "zodiac-snake": "蛇", "zodiac-horse": "馬", "zodiac-goat": "羊",
        "zodiac-monkey": "猴", "zodiac-rooster": "雞", "zodiac-dog": "狗", "zodiac-pig": "豬",
        "aries": "牡羊座", "taurus": "金牛座", "gemini": "雙子座", "cancer": "巨蟹座", "leo": "獅子座",
        "virgo": "處女座", "libra": "天秤座", "scorpio": "天蠍座", "sagittarius": "射手座",
        "capricorn": "摩羯座", "aquarius": "水瓶座", "pisces": "雙魚座",
    ]

    static func bundled(in bundle: Bundle = .main) -> [Page] {
        PageCategory.bundled(in: bundle).flatMap(\.pages)
    }
}

/// A folder of pages under Pages, e.g. "01-vehicles"; its sort order is the home order.
struct PageCategory: Identifiable, Hashable, Sendable {
    let id: String
    let pages: [Page]

    /// For grown-ups, under the card: children go by the picture.
    var name: String { Self.names[String(id.drop { $0 != "-" }.dropFirst())] ?? id }

    static let names = [
        "vehicles": "交通工具", "farm": "農場動物", "wild": "野生動物", "sea": "海洋動物",
        "birds": "鳥類", "bugs": "昆蟲", "dinosaurs": "恐龍", "plants": "花草植物",
        "fruit": "水果", "vegetables": "蔬菜", "food": "點心食物", "buildings": "建築物", "sky": "天空天氣",
        "fantasy": "幻想生物", "zodiac": "十二生肖", "constellations": "十二星座",
    ]

    static func bundled(in bundle: Bundle = .main) -> [PageCategory] {
        guard let root = bundle.url(forResource: "Pages", withExtension: nil) else {
            assertionFailure("Pages folder missing from the bundle — run `make pages`")
            return []
        }
        return subfolders(of: root).map { folder in
            PageCategory(id: folder.lastPathComponent,
                         pages: subfolders(of: folder).map { Page(id: $0.lastPathComponent, directory: $0) })
        }
    }

    private static func subfolders(of url: URL) -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.isDirectoryKey])) ?? [])
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}

enum CanvasSpec {
    /// Square, in pixels, for every page: line art, region map and paint layer alike.
    static let size = 2048
}
