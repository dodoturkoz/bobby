import Foundation

public enum GoldPricePresentationError: Error, LocalizedError, Equatable, Sendable {
    case mismatchedProduct
    case invalidQuote
    case invalidQuantity
    case amountOutOfRange

    public var errorDescription: String? {
        switch self {
        case .mismatchedProduct: return "The returned gold quote does not match the requested product."
        case .invalidQuote: return "The gold quote must have positive prices with dealer buy no greater than dealer sell."
        case .invalidQuantity: return "The gold quantity must be a nonnegative number."
        case .amountOutOfRange: return "The gold value is outside the supported decimal range."
        }
    }
}

/// Presents the dealer's actual product quote, without deriving a coin price
/// from metal weight. Calculations stay decimal-based until display rounding.
public struct GoldPricePresentation: Equatable, Sendable {
    public let valueText: String
    public let detail: String
    public let tooltip: String
    public let copyText: String
    public let showsBothSides: Bool

    public static func make(request: GoldRequest, lookup: GoldLookup,
                            isRefreshing: Bool = false, now: Date = Date()) throws -> GoldPricePresentation {
        let quote = lookup.quote
        guard quote.product == request.product else { throw GoldPricePresentationError.mismatchedProduct }
        guard !quote.dealerBuy.isNaN, !quote.dealerSell.isNaN,
              quote.dealerBuy > 0, quote.dealerSell >= quote.dealerBuy else {
            throw GoldPricePresentationError.invalidQuote
        }
        guard !request.quantity.isNaN, request.quantity >= 0 else { throw GoldPricePresentationError.invalidQuantity }

        let buy: Decimal?
        let sell: Decimal?
        do {
            buy = request.side == .dealerSell ? nil : try CheckedDecimalMath.multiply(request.quantity, quote.dealerBuy)
            sell = request.side == .dealerBuy ? nil : try CheckedDecimalMath.multiply(request.quantity, quote.dealerSell)
        } catch { throw GoldPricePresentationError.amountOutOfRange }
        let buyText = NumberFormatting.string(buy ?? quote.dealerBuy, maximumFractionDigits: 2)
        let sellText = NumberFormatting.string(sell ?? quote.dealerSell, maximumFractionDigits: 2)
        let observed = timestamp(quote.observedAt)
        let source = "\(quote.sourceName) · \(observed)"
        let quantity = NumberFormatting.string(request.quantity, maximumFractionDigits: 8)
        let units = request.quantity == 1 ? request.product.unitDescription : request.product.unitDescription + "s"
        var statuses: [String] = []
        if lookup.usedOfflineCache { statuses.append("offline cache") }
        if now.timeIntervalSince(quote.observedAt) > 15 * 60 { statuses.append("older quote") }
        if isRefreshing { statuses.append("refreshing") }
        // One status fits beside the full observation time even when the two
        // prices need separate lines. All statuses remain in the tooltip/copy.
        let inlineStatus = lookup.usedOfflineCache ? "saved" : statuses.contains("older quote") ? "older" : isRefreshing ? "updating" : nil
        let detail = source + (inlineStatus.map { " · " + $0 } ?? "")

        var tooltipLines = [
            "\(request.product.displayName): \(quantity) \(units)",
            "Dealer buy (you receive): \(buyText) TL\(buy == nil ? " per \(request.product.unitDescription)" : "")",
            "Dealer sell (you pay): \(sellText) TL\(sell == nil ? " per \(request.product.unitDescription)" : "")",
            "\(quote.sourceName) product: \(quote.productLabel) (\(quote.product.rawValue))",
            "Quoted: \(timestamp(quote.observedAt, seconds: true)) Europe/Istanbul",
            "Retrieved: \(timestamp(quote.fetchedAt, seconds: true)) Europe/Istanbul",
            "\(quote.sourceURL.absoluteString)",
            "One dealer's indicative prices in TL. Actual transaction prices may differ."
        ]
        if request.product == .gram {
            tooltipLines.append("Uses the provider's Gram Altın retail listing, not its other gram or bullion listings.")
        } else if ![.oldQuarterCoin, .oldHalfCoin, .oldFullCoin].contains(request.product) {
            tooltipLines.append("Uses the provider's named listing. No mint year is inferred.")
        }
        if lookup.usedOfflineCache {
            tooltipLines.append("Using a saved quote after refreshing failed.")
            if let failure = lookup.failureDescription, !failure.isEmpty { tooltipLines.append(failure) }
        }
        if statuses.contains("older quote") { tooltipLines.append("The provider's quote is over 15 minutes old.") }
        if isRefreshing { tooltipLines.append("Refreshing the dealer's price board.") }

        let valueText: String
        var copyText: String
        switch request.side {
        case .dealerBuy:
            valueText = "Dealer buy: \(buyText) TL"
            copyText = "\(buyText) TL"
        case .dealerSell:
            valueText = "Dealer sell: \(sellText) TL"
            copyText = "\(sellText) TL"
        case nil:
            valueText = "Dealer buy \(buyText) · Dealer sell \(sellText) TL"
            copyText = ["\(request.product.displayName): \(quantity) \(units)",
                        "Dealer buy (you receive): \(buyText) TL",
                        "Dealer sell (you pay): \(sellText) TL",
                        "\(source) Europe/Istanbul",
                        quote.sourceURL.absoluteString].joined(separator: "\n")
            if !statuses.isEmpty { copyText += "\n" + statuses.joined(separator: " · ") }
        }
        return GoldPricePresentation(valueText: valueText, detail: detail,
                                     tooltip: tooltipLines.joined(separator: "\n"), copyText: copyText,
                                     showsBothSides: request.side == nil)
    }

    private static func timestamp(_ date: Date, seconds: Bool = false) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Europe/Istanbul")
        formatter.dateFormat = seconds ? "yyyy-MM-dd HH:mm:ss" : "yyyy-MM-dd HH:mm"
        return formatter.string(from: date)
    }
}
