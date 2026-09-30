import Foundation

/// A complete currency request, or a specific interpretation requiring approval.
/// This recognizes wording only. The calculation engine still validates amounts.
public enum CurrencyInputRecognition: Equatable, Sendable {
    case conversion(amountExpression: String, pair: CurrencyPair, isRateQuery: Bool)
    case suggestion(canonicalExpression: String, question: String)
}

public enum CurrencyInputRecognizer {
    /// Explicit currency names and symbols are accepted without changing the
    /// meaning of ambiguous words such as "lira" or "dollars".
    public static func canonicalCode(for name: String) -> String? {
        let normalized = normalize(name)
        let code = CurrencyPair.canonical(normalized)
        if supportedCodes.contains(code) { return code }
        return aliases[normalized]
    }

    public static func recognize(_ text: String) -> CurrencyInputRecognition? {
        let input = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return nil }

        // A complete pair without an amount is a request for the unit rate.
        if let values = captures(input, pattern: "^(\(currencyPattern))\(pairSeparator)(\(currencyPattern))$") {
            return recognition(amount: "1", source: values[0], destination: values[1], isRateQuery: true)
        }

        // Whitespace separates currency names from variables and expressions.
        // Compact numeric amounts such as 3USD have a separate narrow pattern.
        if let values = captures(input, pattern: "^(.+?)\\s+(\(currencyPattern))\(pairSeparator)(\(currencyPattern))$"),
           plausibleAmount(values[0]) {
            return recognition(amount: values[0], source: values[1], destination: values[2], isRateQuery: false)
        }
        if let values = captures(input, pattern: "^(\(numberPattern))\\s*(\(currencyPattern))\(pairSeparator)(\(currencyPattern))$") {
            return recognition(amount: values[0], source: values[1], destination: values[2], isRateQuery: false)
        }

        // Prefix symbols are useful for pasted amounts. A bare $ remains a
        // confirmation, since several currencies use that symbol.
        if let values = captures(input, pattern: "^(€|₺|US\\$|\\$)\\s*(\(numberPattern))\(explicitSeparator)(\(currencyPattern))$") {
            return recognition(amount: values[1], source: values[0], destination: values[2], isRateQuery: false)
        }
        return nil
    }

    private static func recognition(amount: String, source: String, destination: String,
                                    isRateQuery: Bool) -> CurrencyInputRecognition? {
        guard let sourceMeaning = meaning(source), let destinationMeaning = meaning(destination) else { return nil }
        let pair = CurrencyPair(base: sourceMeaning.code, quote: destinationMeaning.code)
        let questions = [sourceMeaning.confirmation, destinationMeaning.confirmation].compactMap { $0 }
        guard !questions.isEmpty else {
            return .conversion(amountExpression: amount.trimmingCharacters(in: .whitespaces),
                               pair: pair, isRateQuery: isRateQuery)
        }
        let names = Array(Set(questions)).sorted()
        let question = "Do you mean " + names.joined(separator: " and ") + "?"
        let amountPrefix = isRateQuery ? "" : amount.trimmingCharacters(in: .whitespaces) + " "
        let canonical = "\(amountPrefix)\(displayCode(pair.base)) to \(displayCode(pair.quote))"
        return .suggestion(canonicalExpression: canonical, question: question)
    }

    private static func meaning(_ name: String) -> (code: String, confirmation: String?)? {
        if let code = canonicalCode(for: name) { return (code, nil) }
        switch normalize(name) {
        case "lira", "liras": return ("TRY", "Turkish lira")
        case "dollar", "dollars", "$": return ("USD", "U.S. dollars")
        default: return nil
        }
    }

    private static func plausibleAmount(_ text: String) -> Bool {
        guard text.range(of: #"[^\p{L}\p{N}_\s.,+*/^()%×÷−\-]"#, options: .regularExpression) == nil else { return false }
        // Consecutive prose words are not an amount. A quantity followed by its
        // ISO currency is allowed, and the existing parser checks its meaning.
        guard let regex = try? NSRegularExpression(pattern: #"([\p{L}_][\p{L}\p{N}_]*)\s+([\p{L}_][\p{L}\p{N}_]*)"#) else { return false }
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
        for match in matches {
            guard let range = Range(match.range(at: 2), in: text),
                  supportedCodes.contains(CurrencyPair.canonical(String(text[range]))) else { return false }
        }
        return true
    }

    private static func displayCode(_ code: String) -> String { code == "TRY" ? "TL" : code }

    private static func normalize(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .lowercased()
    }

    private static func captures(_ text: String, pattern: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return (1..<match.numberOfRanges).map { index in
            guard let range = Range(match.range(at: index), in: text) else { return "" }
            return String(text[range])
        }
    }

    private static let supportedCodes: Set<String> = [
        "AED", "AUD", "AZN", "BGN", "BHD", "BRL", "CAD", "CHF", "CNY", "CZK", "DKK", "EGP",
        "EUR", "GBP", "GEL", "HKD", "HUF", "IDR", "ILS", "INR", "ISK", "JPY", "KRW", "KWD",
        "KZT", "MXN", "MYR", "NOK", "NZD", "PHP", "PLN", "QAR", "RON", "RUB", "SAR", "SEK",
        "SGD", "THB", "TRY", "TWD", "UAH", "USD", "VND", "ZAR"
    ]

    private static let aliases: [String: String] = [
        "euro": "EUR", "euros": "EUR", "€": "EUR",
        "turkish lira": "TRY", "turkish liras": "TRY", "türk lirası": "TRY", "turk lirasi": "TRY", "₺": "TRY",
        "us dollar": "USD", "us dollars": "USD", "u.s. dollar": "USD", "u.s. dollars": "USD",
        "united states dollar": "USD", "united states dollars": "USD", "us$": "USD",
        "british pound": "GBP", "british pounds": "GBP", "pound sterling": "GBP", "pounds sterling": "GBP",
        "swiss franc": "CHF", "swiss francs": "CHF",
        "japanese yen": "JPY", "yen": "JPY",
        "canadian dollar": "CAD", "canadian dollars": "CAD",
        "australian dollar": "AUD", "australian dollars": "AUD",
        "new zealand dollar": "NZD", "new zealand dollars": "NZD",
        "hong kong dollar": "HKD", "hong kong dollars": "HKD",
        "singapore dollar": "SGD", "singapore dollars": "SGD",
        "chinese yuan": "CNY", "renminbi": "CNY",
        "indian rupee": "INR", "indian rupees": "INR",
        "south african rand": "ZAR"
    ]

    private static let numberPattern = #"[+−-]?(?:\d[\d,.]*|\.\d+)[kKmM]?"#
    private static let explicitSeparator = #"\s*(?:\b(?:to|in|into)\b|->|→)\s*"#
    private static let pairSeparator = #"(?:\s*(?:\b(?:to|in|into)\b|->|→|/)\s*|\s+)"#
    private static let currencyPattern: String = {
        let names = Array(supportedCodes) + ["TL"] + Array(aliases.keys) + ["lira", "liras", "dollar", "dollars", "$"]
        return names.sorted { $0.count > $1.count }.map {
            NSRegularExpression.escapedPattern(for: $0).replacingOccurrences(of: " ", with: #"\s+"#)
        }.joined(separator: "|")
    }()
}
