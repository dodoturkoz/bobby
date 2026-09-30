import Foundation

/// An explicit proposal, rather than a calculated answer. The user must review
/// the annual rate, simple-interest assumption, and any missing principal.
public struct FinanceSuggestion: Equatable, Sendable {
    public let title: String
    public let detail: String
    public let interest: InterestDraft

    public init(interest: InterestDraft) {
        self.interest = interest
        title = "Do you mean simple interest?"
        detail = interest.principal == nil
            ? "Review the annual rate and duration, then enter a principal."
            : "Review the annual rate, duration, and no-compounding assumption."
    }
}

public struct InterestDuration: Equatable, Sendable {
    public enum Unit: String, Equatable, Sendable {
        case days
        case years
    }

    public let value: Decimal
    public let unit: Unit

    public init(value: Decimal, unit: Unit) {
        self.value = value
        self.unit = unit
    }

    public var displayText: String {
        let label = value == 1 ? (unit == .days ? "day" : "year") : unit.rawValue
        return "\(NumberFormatting.string(value)) \(label)"
    }

    public func elapsedDays(yearBasis: Int) throws -> Decimal {
        guard !value.isNaN, value >= 0 else { throw InterestDraftError.invalidDuration }
        guard yearBasis > 0 else { throw InterestDraftError.invalidYearBasis }
        guard unit == .years else { return value }
        return try SuggestionDecimal.multiply(value, Decimal(yearBasis))
    }
}

public enum InterestDraftError: Error, Equatable, LocalizedError, Sendable {
    case missingPrincipal
    case invalidPrincipal
    case invalidRate
    case invalidDuration
    case invalidYearBasis
    case unsupportedCurrency
    case decimalRange

    public var errorDescription: String? {
        switch self {
        case .missingPrincipal: return "Enter the principal before calculating interest."
        case .invalidPrincipal: return "The principal must be a number zero or greater."
        case .invalidRate: return "Enter a valid annual percentage rate."
        case .invalidDuration: return "The duration must be a number zero or greater."
        case .invalidYearBasis: return "The interest year basis must be greater than zero."
        case .unsupportedCurrency: return "Use a supported currency code or an unambiguous currency name."
        case .decimalRange: return "The amount or duration is outside the supported decimal range."
        }
    }
}

public struct InterestDraft: Equatable, Sendable {
    public let principal: Decimal?
    public let currency: String?
    /// A percentage, for example 42 means 42% per year, not the scalar 0.42.
    public let annualRatePercent: Decimal
    public let duration: InterestDuration

    public init(principal: Decimal?, currency: String?, annualRatePercent: Decimal,
                duration: InterestDuration) {
        self.principal = principal
        self.currency = currency.map(CurrencyPair.canonical)
        self.annualRatePercent = annualRatePercent
        self.duration = duration
    }

    /// Produces the calculator's documented syntax only after the caller has
    /// reviewed the proposal. A missing principal is never replaced with 1.
    /// Nil overrides retain any principal and currency supplied in the phrase.
    /// The basis is written into the line so later global settings cannot alter it.
    public func canonicalExpression(principal suppliedPrincipal: Decimal? = nil,
                                    currency suppliedCurrency: String? = nil,
                                    yearBasis: Int = 365) throws -> String {
        guard let principal = suppliedPrincipal ?? principal else { throw InterestDraftError.missingPrincipal }
        guard !principal.isNaN, principal >= 0 else { throw InterestDraftError.invalidPrincipal }
        guard !annualRatePercent.isNaN else { throw InterestDraftError.invalidRate }
        let days = try duration.elapsedDays(yearBasis: yearBasis)
        let requestedCurrency = suppliedCurrency ?? currency
        let currencySuffix: String
        if let requestedCurrency, !requestedCurrency.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            guard let canonical = CurrencyInputRecognizer.canonicalCode(for: requestedCurrency) else {
                throw InterestDraftError.unsupportedCurrency
            }
            currencySuffix = " \(canonical == "TRY" ? "TL" : canonical)"
        } else {
            currencySuffix = ""
        }
        return "\(SuggestionDecimal.literal(principal))\(currencySuffix) at \(SuggestionDecimal.literal(annualRatePercent))% for \(SuggestionDecimal.literal(days)) days basis \(yearBasis)"
    }

    public func reviewDetail(yearBasis: Int = 365) -> String {
        let rate = NumberFormatting.string(annualRatePercent)
        let base = "Simple interest at an annual \(rate)% for \(duration.displayText). No compounding."
        if duration.unit == .years, let days = try? duration.elapsedDays(yearBasis: yearBasis) {
            return "\(base) Each year is \(yearBasis) days (\(NumberFormatting.string(days)) days total), using Actual/\(yearBasis)."
        }
        return "\(base) Using Actual/\(yearBasis)."
    }
}

/// Small, fully anchored finance phrases. This does not search arbitrary prose,
/// infer currencies, infer a principal, or offer a compound-interest calculation.
public enum FinanceInputSuggestions {
    public static func suggestion(for rawLine: String) -> FinanceSuggestion? {
        let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty, line.count <= 512, !line.contains("\n") else { return nil }

        for pattern in englishPatterns {
            guard let captures = captures(in: line, pattern: pattern),
                  let rateText = captures["rate"], let rate = number(rateText),
                  let durationText = captures["duration"], let duration = number(durationText),
                  let unitText = captures["unit"] else { continue }
            var principal: Decimal?
            var currency: String?
            if let principalText = captures["principal"] {
                guard let parsedPrincipal = amount(principalText) else { continue }
                principal = parsedPrincipal
            }
            if let currencyText = captures["currency"] {
                guard let code = CurrencyInputRecognizer.canonicalCode(for: currencyText) else { continue }
                currency = code
            }
            let unit: InterestDuration.Unit = unitText.lowercased().hasPrefix("year") ? .years : .days
            return FinanceSuggestion(interest: InterestDraft(principal: principal, currency: currency,
                annualRatePercent: rate, duration: InterestDuration(value: duration, unit: unit)))
        }

        // The requested Turkish phrase is supported conservatively. "3 yıllık"
        // proposes three years, with the annual/simple assumptions shown for review.
        if let captures = captures(in: line, pattern: turkishPattern),
           let rateText = captures["rate"], let rate = number(rateText),
           let durationText = captures["duration"], let duration = number(durationText),
           let unitText = captures["unit"] {
            let lowerUnit = unitText.lowercased()
            let unit: InterestDuration.Unit = lowerUnit.hasPrefix("g") ? .days : .years
            return FinanceSuggestion(interest: InterestDraft(principal: nil, currency: nil,
                annualRatePercent: rate, duration: InterestDuration(value: duration, unit: unit)))
        }
        return nil
    }

    private static let literal = #"(?:(?:[0-9]+|[0-9]{1,3}(?:,[0-9]{3})+)(?:\.[0-9]+)?|\.[0-9]+)"#
    private static let amountLiteral = "\(literal)[kKmM]?"
    private static let principal = "(?<principal>\(amountLiteral))(?:\\s+(?<currency>[\\p{L}.$€₺]+(?:\\s+[\\p{L}.$€₺]+){0,3}))?"
    private static let rate = "(?<rate>-?\(literal))\\s*(?:%|percent)(?:\\s+(?:annually|per\\s+year))?"
    private static let duration = "(?<duration>\(literal))(?:\\s*-\\s*|\\s+)(?<unit>days?|years?)"
    private static let yearDuration = "(?<duration>\(literal))(?:\\s*-\\s*|\\s+)(?<unit>years?)"
    private static let englishPatterns = [
        "^(?:simple\\s+)?interest\\s+on\\s+\(principal)\\s+at\\s+\(rate)\\s+for\\s+\(duration)$",
        "^(?:simple\\s+)?interest\\s+on\\s+\(principal)\\s+for\\s+\(duration)\\s+at\\s+\(rate)$",
        // Existing `amount at rate for days` expressions already calculate
        // directly. Only the new years form needs an explicit review here.
        "^\(principal)\\s+at\\s+\(rate)\\s+for\\s+\(yearDuration)$",
        "^\(duration)\\s+(?:simple\\s+)?interest\\s+at\\s+\(rate)$",
        "^(?:simple\\s+)?interest\\s+for\\s+\(duration)\\s+at\\s+\(rate)$",
        "^(?:simple\\s+)?interest\\s+at\\s+\(rate)\\s+for\\s+\(duration)$"
    ]
    private static let turkishPattern = "^(?<duration>\(literal))\\s+(?<unit>yıllık|yillik|yıl|yil|sene|günlük|gunluk|gün|gun)\\s+faiz\\s+(?:yüzde|yuzde|%)\\s*(?<rate>-?\(literal))(?:['’]?(?:den|dan))?$"

    private static func captures(in text: String, pattern: String) -> [String: String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        var captures: [String: String] = [:]
        for name in ["principal", "currency", "rate", "duration", "unit"] {
            guard pattern.contains("?<\(name)>"),
                  let range = Range(match.range(withName: name), in: text) else { continue }
            captures[name] = String(text[range])
        }
        return captures
    }

    private static func number(_ text: String) -> Decimal? {
        let literal = text.replacingOccurrences(of: ",", with: "")
        guard let value = Decimal(string: literal, locale: Locale(identifier: "en_US_POSIX")), !value.isNaN else { return nil }
        return value
    }

    private static func amount(_ text: String) -> Decimal? {
        let lower = text.lowercased()
        let multiplier: Decimal
        let literal: String
        if lower.hasSuffix("k") || lower.hasSuffix("m") {
            multiplier = lower.hasSuffix("k") ? 1_000 : 1_000_000
            literal = String(text.dropLast())
        } else {
            multiplier = 1
            literal = text
        }
        guard let value = number(literal) else { return nil }
        return try? SuggestionDecimal.multiply(value, multiplier)
    }
}

private enum SuggestionDecimal {
    static func literal(_ value: Decimal) -> String {
        NSDecimalNumber(decimal: value).stringValue
    }

    static func multiply(_ lhs: Decimal, _ rhs: Decimal) throws -> Decimal {
        do { return try CheckedDecimalMath.multiply(lhs, rhs) }
        catch { throw InterestDraftError.decimalRange }
    }
}
