import AppKit
import CryptoKit
import SwiftUI

enum ClipKind: Int {
    case text = 0, link, code, color, image, file

    var symbol: String {
        switch self {
        case .text: return "text.alignleft"
        case .link: return "link"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .color: return "paintpalette"
        case .image: return "photo"
        case .file: return "doc"
        }
    }

    var isMonospaced: Bool { self == .code || self == .color }
}

struct ClipItem: Identifiable {
    let id: Int64
    let kind: ClipKind
    /// Testo completo; per i file i percorsi separati da a capo; per le immagini una descrizione.
    let text: String
    let imageFile: String?
    let width: Int
    let height: Int
    let byteCount: Int
    let sourceName: String?
    let sourceBundle: String?
    let copiedAt: Date
    let hash: String
    /// Una riga sola, già accorciata, per l'elenco.
    let title: String
    /// Testo normalizzato (minuscole, senza accenti) in UTF-8 per la ricerca full text.
    let searchKey: [UInt8]

    init(id: Int64, kind: ClipKind, text: String, imageFile: String?, width: Int, height: Int, byteCount: Int,
         sourceName: String?, sourceBundle: String?, copiedAt: Date, hash: String) {
        self.id = id
        self.kind = kind
        self.text = text
        self.imageFile = imageFile
        self.width = width
        self.height = height
        self.byteCount = byteCount
        self.sourceName = sourceName
        self.sourceBundle = sourceBundle
        self.copiedAt = copiedAt
        self.hash = hash
        title = ClipItem.makeTitle(kind: kind, text: text)
        searchKey = Array(Search.fold(text + "\n" + (sourceName ?? "")).utf8)
    }

    func with(kind: ClipKind? = nil, copiedAt: Date, sourceName: String?, sourceBundle: String?) -> ClipItem {
        ClipItem(id: id, kind: kind ?? self.kind, text: text, imageFile: imageFile, width: width, height: height,
                 byteCount: byteCount, sourceName: sourceName, sourceBundle: sourceBundle, copiedAt: copiedAt, hash: hash)
    }

    func matches(_ needle: [UInt8]) -> Bool {
        if needle.isEmpty { return true }
        if searchKey.count < needle.count { return false }
        return searchKey.withUnsafeBufferPointer { hay in
            needle.withUnsafeBufferPointer { n in
                memmem(hay.baseAddress, hay.count, n.baseAddress, n.count) != nil
            }
        }
    }

    private static func makeTitle(kind: ClipKind, text: String) -> String {
        switch kind {
        case .link:
            var value = text.trimmingCharacters(in: .whitespacesAndNewlines)
            for scheme in ["https://", "http://"] where value.lowercased().hasPrefix(scheme) {
                value.removeFirst(scheme.count)
            }
            return String(value.prefix(300))
        case .file:
            return text.split(separator: "\n").map { URL(fileURLWithPath: String($0)).lastPathComponent }.joined(separator: ", ")
        case .image, .color:
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        case .text, .code:
            var out = ""
            var pendingSpace = false
            for char in text.prefix(400) {
                if char.isWhitespace || char.isNewline {
                    pendingSpace = !out.isEmpty
                } else {
                    if pendingSpace { out.append(" "); pendingSpace = false }
                    out.append(char)
                }
            }
            return out
        }
    }
}

// MARK: - Dettagli per l'anteprima

extension ClipItem {
    var previewText: String {
        guard text.utf16.count > 20_000 else { return text }
        return String(text.prefix(20_000)) + "\n…"
    }

    var linkHost: String { URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines))?.host ?? "" }

    var swatch: Color? {
        ColorParser.parse(text).map { Color(.sRGB, red: $0.r, green: $0.g, blue: $0.b, opacity: $0.a) }
    }

    var fileURLs: [URL] { text.split(separator: "\n").map { URL(fileURLWithPath: String($0)) } }

    var metadata: [(String, String)] {
        var rows: [(String, String)] = [
            ("Origine", sourceName ?? "Sconosciuta"),
            ("Copiato", DayFormat.copied(copiedAt)),
        ]
        switch kind {
        case .text:
            let chars = text.count
            let words = text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
            rows.append(("Contenuto", "\(Numbers.format(chars)) \(chars == 1 ? "carattere" : "caratteri") · \(Numbers.format(words)) \(words == 1 ? "parola" : "parole")"))
        case .code:
            let lines = text.split(separator: "\n", omittingEmptySubsequences: false).count
            let chars = text.count
            rows.append(("Contenuto", "\(Numbers.format(lines)) \(lines == 1 ? "riga" : "righe") · \(Numbers.format(chars)) \(chars == 1 ? "carattere" : "caratteri")"))
        case .link:
            rows.append(("Contenuto", linkHost.isEmpty ? "Link" : "Link · \(linkHost)"))
        case .color:
            rows.append(("Valori", ColorParser.parse(text).map(ColorParser.rgbString) ?? text))
        case .image:
            let size = ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file)
            rows.append(("Immagine", "PNG · \(width) × \(height) · \(size)"))
        case .file:
            let urls = fileURLs
            if urls.count == 1, let url = urls.first {
                rows.append(("File", Self.fileDescription(url)))
            } else {
                rows.append(("File", "\(urls.count) file"))
            }
        }
        return rows
    }

    private static func fileDescription(_ url: URL) -> String {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) else {
            return "Non più disponibile"
        }
        if (attributes[.type] as? FileAttributeType) == .typeDirectory { return "Cartella" }
        let size = ByteCountFormatter.string(fromByteCount: (attributes[.size] as? NSNumber)?.int64Value ?? 0, countStyle: .file)
        let ext = url.pathExtension.uppercased()
        return ext.isEmpty ? size : "\(ext) · \(size)"
    }
}

// MARK: - Ricerca

enum Search {
    static func fold(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }

    static func terms(_ query: String) -> [String] {
        fold(query).split(whereSeparator: { $0.isWhitespace }).map(String.init)
    }
}

// MARK: - Riconoscimento del tipo

enum Detect {
    private static let codeApps: Set<String> = [
        "com.microsoft.VSCode", "com.microsoft.VSCodeInsiders", "com.apple.dt.Xcode", "com.apple.Terminal",
        "com.googlecode.iterm2", "dev.zed.Zed", "com.sublimetext.4", "com.sublimetext.3",
        "com.todesktop.230313mzl4w4u92", "com.mitchellh.ghostty", "dev.warp.Warp-Stable", "com.panic.Nova",
        "net.kovidgoyal.kitty", "org.alacritty", "com.exafunction.windsurf",
    ]

    static func kind(for text: String, sourceBundle: String?) -> ClipKind {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= 40, ColorParser.parse(trimmed) != nil { return .color }
        if trimmed.count < 4096, !trimmed.contains(where: { $0.isWhitespace }),
           let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(),
           scheme == "http" || scheme == "https", url.host != nil {
            return .link
        }
        let fromCodeApp = sourceBundle.map { codeApps.contains($0) || $0.hasPrefix("com.jetbrains.") } ?? false
        if fromCodeApp, trimmed.contains(where: { "(){}[];=<>".contains($0) }) { return .code }
        if looksLikeCode(trimmed) { return .code }
        return .text
    }

    private static func looksLikeCode(_ text: String) -> Bool {
        let lines = text.prefix(4000).split(separator: "\n", omittingEmptySubsequences: true)
        guard lines.count >= 3 else { return false }
        let prefixes = ["//", "#include", "import ", "from ", "def ", "func ", "fn ", "const ", "let ", "var ", "return ", "public ", "private ", "class ", "SELECT ", "WHERE "]
        let suffixes = [";", "{", "}", "};", "):", "=>"]
        var score = 0
        for line in lines {
            let value = line.trimmingCharacters(in: .whitespaces)
            if suffixes.contains(where: { value.hasSuffix($0) }) || prefixes.contains(where: { value.hasPrefix($0) }) {
                score += 1
            }
        }
        return Double(score) / Double(lines.count) >= 0.4
    }
}

enum ColorParser {
    struct RGBA { var r, g, b, a: Double }

    /// Riconosce `#RRGGBB`, `#RRGGBBAA`, `rgb(…)` e `rgba(…)`.
    static func parse(_ value: String) -> RGBA? {
        let text = value.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("#") {
            let hex = text.dropFirst()
            guard hex.count == 6 || hex.count == 8, hex.allSatisfy(\.isHexDigit), let v = UInt64(hex, radix: 16) else { return nil }
            if hex.count == 6 {
                return RGBA(r: Double((v >> 16) & 0xFF) / 255, g: Double((v >> 8) & 0xFF) / 255, b: Double(v & 0xFF) / 255, a: 1)
            }
            return RGBA(r: Double((v >> 24) & 0xFF) / 255, g: Double((v >> 16) & 0xFF) / 255, b: Double((v >> 8) & 0xFF) / 255, a: Double(v & 0xFF) / 255)
        }
        let lower = text.lowercased()
        guard lower.hasPrefix("rgb(") || lower.hasPrefix("rgba("), lower.hasSuffix(")"),
              let open = lower.firstIndex(of: "(") else { return nil }
        let inner = lower[lower.index(after: open)..<lower.index(before: lower.endIndex)]
        let parts = inner.split(whereSeparator: { $0 == "," || $0 == " " || $0 == "/" }).map(String.init)
        guard parts.count == 3 || parts.count == 4 else { return nil }
        func channel(_ part: String) -> Double? {
            if part.hasSuffix("%") { return Double(part.dropLast()).map { $0 / 100 } }
            return Double(part).map { $0 / 255 }
        }
        guard let r = channel(parts[0]), let g = channel(parts[1]), let b = channel(parts[2]),
              [r, g, b].allSatisfy({ (0...1).contains($0) }) else { return nil }
        var alpha = 1.0
        if parts.count == 4 {
            alpha = parts[3].hasSuffix("%") ? (Double(parts[3].dropLast()) ?? 100) / 100 : (Double(parts[3]) ?? 1)
        }
        return RGBA(r: r, g: g, b: b, a: min(max(alpha, 0), 1))
    }

    static func rgbString(_ c: RGBA) -> String {
        let r = Int((c.r * 255).rounded()), g = Int((c.g * 255).rounded()), b = Int((c.b * 255).rounded())
        return c.a < 1 ? "rgba(\(r), \(g), \(b), \(String(format: "%.2f", c.a)))" : "rgb(\(r), \(g), \(b))"
    }
}

// MARK: - Date e numeri

enum DayFormat {
    private static let locale = Locale(identifier: "it_IT")

    private static let weekday: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateFormat = "EEEE"
        return formatter
    }()

    private static let weekdayAndDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateFormat = "EEEE d MMMM"
        return formatter
    }()

    static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    static func dayKey(_ date: Date) -> Date { Calendar.current.startOfDay(for: date) }

    static func dayLabel(_ date: Date, now: Date = Date()) -> String {
        let calendar = Calendar.current
        let diff = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 0
        switch diff {
        case ...0: return "Oggi"
        case 1: return "Ieri"
        case 2..<7: return weekday.string(from: date).capitalizedFirst
        default: return weekdayAndDate.string(from: date).capitalizedFirst
        }
    }

    static func copied(_ date: Date) -> String { "\(dayLabel(date)) alle \(time.string(from: date))" }
}

enum Numbers {
    private static let formatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "it_IT")
        formatter.numberStyle = .decimal
        return formatter
    }()

    static func format(_ value: Int) -> String { formatter.string(from: NSNumber(value: value)) ?? String(value) }
}

enum Hashing {
    static func hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

extension String {
    var capitalizedFirst: String { prefix(1).uppercased() + dropFirst() }
}
