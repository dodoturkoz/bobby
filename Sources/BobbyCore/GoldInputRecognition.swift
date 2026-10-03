import Foundation

/// Identifiers match Altınkaynak's named retail products. A standard listing
/// does not assert the coin's mint year, and packaged gram gold remains distinct.
public enum GoldProduct: String, Codable, Hashable, Sendable, CaseIterable {
    case quarterCoin = "PC"
    case oldQuarterCoin = "EC"
    case halfCoin = "PY"
    case oldHalfCoin = "EY"
    case fullCoin = "PT"
    case oldFullCoin = "ET"
    case ataCoin = "PA"
    case gram = "PGA"

    public var displayName: String {
        switch self {
        case .quarterCoin: return "Quarter gold"
        case .oldQuarterCoin: return "Old quarter gold"
        case .halfCoin: return "Half gold"
        case .oldHalfCoin: return "Old half gold"
        case .fullCoin: return "Full gold"
        case .oldFullCoin: return "Old full gold"
        case .ataCoin: return "Ata gold"
        case .gram: return "Gram gold"
        }
    }

    public var providerName: String {
        switch self {
        case .quarterCoin: return "Çeyrek"
        case .oldQuarterCoin: return "Eski Çeyrek"
        case .halfCoin: return "Yarım"
        case .oldHalfCoin: return "Eski Yarım"
        case .fullCoin: return "Teklik"
        case .oldFullCoin: return "Eski Teklik"
        case .ataCoin: return "Ata Cumhuriyet"
        case .gram: return "Gram Altın"
        }
    }

    public var unitDescription: String { self == .gram ? "gram" : "coin" }
}

public enum GoldSide: String, Codable, Sendable {
    case dealerBuy
    case dealerSell

    public var displayName: String { self == .dealerBuy ? "Dealer buy" : "Dealer sell" }
}

public struct GoldRequest: Equatable, Sendable {
    public let product: GoldProduct
    public let quantity: Decimal
    public let side: GoldSide?

    public init(product: GoldProduct, quantity: Decimal = 1, side: GoldSide? = nil) {
        self.product = product
        self.quantity = quantity
        self.side = side
    }
}

/// Recognition identifies only the product and side. The calculation engine
/// parses the quantity with the same decimal rules as other expressions.
public enum GoldInputRecognition: Equatable, Sendable {
    case gold(product: GoldProduct, quantityExpression: String, side: GoldSide?)
}

public enum GoldInputRecognizer {
    public static func recognize(_ text: String) -> GoldInputRecognition? {
        let input = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var words = input.split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty else { return nil }

        var side: GoldSide?
        if let last = words.last {
            switch normalize(String(last)) {
            case "alis", "buy": side = .dealerBuy
            case "satis", "sell": side = .dealerSell
            default: break
            }
            if side != nil {
                words.removeLast()
                if words.last.map({ normalize(String($0)) }) == "dealer" { words.removeLast() }
            }
        }

        for alias in aliases {
            guard words.count >= alias.words.count else { continue }
            let productWords = words.suffix(alias.words.count)
            guard zip(productWords, alias.words).allSatisfy({ normalize(String($0.0)) == $0.1 }),
                  let firstProductWord = productWords.first else { continue }
            let quantity = input[..<firstProductWord.startIndex].trimmingCharacters(in: .whitespacesAndNewlines)
            guard quantity.isEmpty || plausibleQuantity(quantity) else { continue }
            return .gold(product: alias.product, quantityExpression: quantity.isEmpty ? "1" : quantity, side: side)
        }
        return nil
    }

    private static func normalize(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .replacingOccurrences(of: "ı", with: "i")
            .lowercased()
    }

    private struct Alias {
        let product: GoldProduct
        let words: [String]
    }

    private static let aliases: [Alias] = {
        let names: [(GoldProduct, [String])] = [
            (.quarterCoin, ["ceyrek altin", "ceyrek altini", "quarter gold", "quarter gold coin"]),
            (.oldQuarterCoin, ["eski ceyrek altin", "eski ceyrek altini", "old quarter gold", "old quarter gold coin"]),
            (.halfCoin, ["yarim altin", "yarim altini", "half gold", "half gold coin"]),
            (.oldHalfCoin, ["eski yarim altin", "eski yarim altini", "old half gold", "old half gold coin"]),
            (.fullCoin, ["tam altin", "tam altini", "teklik altin", "teklik altini", "full gold", "full gold coin"]),
            (.oldFullCoin, ["eski tam altin", "eski tam altini", "eski teklik altin", "eski teklik altini", "old full gold", "old full gold coin"]),
            (.ataCoin, ["ata altin", "ata altini", "cumhuriyet altin", "cumhuriyet altini", "ata cumhuriyet altin", "ata cumhuriyet altini", "ata gold", "ata gold coin", "ata coin", "republic gold", "republic gold coin"]),
            (.gram, ["gram altin", "gram altini", "gram gold"])
        ]
        return names.flatMap { product, names in
            names.map { Alias(product: product, words: $0.split(separator: " ").map(String.init)) }
        }.sorted { lhs, rhs in
            if lhs.words.count != rhs.words.count { return lhs.words.count > rhs.words.count }
            return lhs.words.joined(separator: " ") < rhs.words.joined(separator: " ")
        }
    }()

    private static func plausibleQuantity(_ text: String) -> Bool {
        guard text.range(of: #"[^\p{L}\p{N}_\s.,+*/^()%×÷−\-]"#, options: .regularExpression) == nil,
              let regex = try? NSRegularExpression(pattern: #"(?:[0-9][0-9,.]*|\.[0-9]+)[kKmM]?|[\p{L}_][\p{L}\p{N}_]*|[+*/^()%×÷−\-]"#) else { return false }
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        var previousEndsOperand = false
        for match in matches {
            guard let range = Range(match.range, in: text) else { return false }
            let token = String(text[range])
            let isIdentifier = token.range(of: #"^[\p{L}_]"#, options: .regularExpression) != nil
            let isNumber = token.first?.isNumber == true || token.first == "."
            let startsOperand = isIdentifier || isNumber || token == "("
            if previousEndsOperand && startsOperand {
                // Keep money literals recognizable so the engine can explain
                // that a gold quantity must be a plain number.
                guard isIdentifier, CurrencyInputRecognizer.canonicalCode(for: token) != nil else { return false }
            }
            previousEndsOperand = isIdentifier || isNumber || token == ")" || token == "%"
        }
        return !matches.isEmpty
    }
}
