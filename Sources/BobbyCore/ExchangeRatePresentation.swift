import Foundation

public enum ExchangeRatePresentationError: Error, LocalizedError, Equatable, Sendable {
    case invalidRate
    case mismatchedPair
    case amountOutOfRange
    case invalidRateQueryAmount

    public var errorDescription: String? {
        switch self {
        case .invalidRate:
            return "The exchange rate is invalid. Rates must be positive, and same-currency rates must equal 1."
        case .mismatchedPair:
            return "The returned quote does not match the requested currency pair."
        case .amountOutOfRange:
            return "The converted amount is outside the supported decimal range."
        case .invalidRateQueryAmount:
            return "A unit-rate query must use an amount of 1."
        }
    }
}

/// Network-free presentation of a dated quote. A unit rate has more precision
/// than a rounded monetary amount, and its denominator stays visible.
public struct ExchangeRatePresentation: Equatable, Sendable {
    public let valueText: String
    public let detail: String
    public let tooltip: String
    public let copyText: String

    public static func make(request: ConversionRequest, lookup: RateLookup,
                            isRefreshing: Bool = false) throws -> ExchangeRatePresentation {
        let pair = request.pair
        let quote = lookup.quote
        guard pair == quote.pair else { throw ExchangeRatePresentationError.mismatchedPair }
        guard !quote.rate.isNaN, quote.rate > 0,
              pair.base != pair.quote || quote.rate == 1 else {
            throw ExchangeRatePresentationError.invalidRate
        }
        guard !request.amount.isNaN else { throw ExchangeRatePresentationError.amountOutOfRange }
        guard !request.isRateQuery || request.amount == 1 else {
            throw ExchangeRatePresentationError.invalidRateQueryAmount
        }

        let value: Decimal
        do {
            value = try CheckedDecimalMath.multiply(request.amount, quote.rate)
        } catch {
            throw ExchangeRatePresentationError.amountOutOfRange
        }

        let sourceCurrency = displayCode(pair.base)
        let destinationCurrency = displayCode(pair.quote)
        let digits = request.isRateQuery ? 8 : 2
        let copiedValue = NumberFormatting.string(value, maximumFractionDigits: digits) + " " + destinationCurrency
        let rateText = "1 \(sourceCurrency) = \(NumberFormatting.string(quote.rate, maximumFractionDigits: 8)) \(destinationCurrency)"
        let displayedValue = request.isRateQuery ? rateText : copiedValue

        let source = pair.base == pair.quote ? "Identity rate" : "Frankfurter"
        var details = [source, quote.observedDate]
        if lookup.usedOfflineCache { details.append("offline cache") }
        if isRefreshing { details.append("refreshing") }

        var tooltipLines = [rateText, quote.sourceLabel, quote.rateType, "Rate date: \(quote.observedDate)"]
        if lookup.usedOfflineCache {
            tooltipLines.append("Using a saved quote after refreshing failed.")
            if let failure = lookup.failureDescription, !failure.isEmpty { tooltipLines.append(failure) }
        }
        if isRefreshing { tooltipLines.append("Refreshing the reference quote.") }

        return ExchangeRatePresentation(valueText: displayedValue, detail: details.joined(separator: " · "),
                                        tooltip: tooltipLines.joined(separator: "\n"), copyText: copiedValue)
    }

    private static func displayCode(_ code: String) -> String { code == "TRY" ? "TL" : code }
}
