import Foundation

/// Separates copyable result values from the engine's descriptive titles.
public enum CalculationPresentation {
    public static func valueText(_ evaluation: LineEvaluation) -> String {
        guard evaluation.kind != .error, let value = evaluation.value else {
            return evaluation.title
        }
        let digits = evaluation.currency != nil || evaluation.kind == .interest ? 2 : 8
        return formatted(value, currency: evaluation.currency, digits: digits)
    }

    public static func detail(_ evaluation: LineEvaluation) -> String {
        if let interest = evaluation.interest, evaluation.kind == .interest {
            let total = formatted(interest.total, currency: interest.currency, digits: 2)
            return "Final: \(total) · Actual/\(NumberFormatting.string(interest.yearBasis))"
        }
        return evaluation.detail ?? ""
    }

    public static func tooltip(_ evaluation: LineEvaluation) -> String {
        if evaluation.kind == .error {
            return evaluation.detail ?? evaluation.title
        }
        if let interest = evaluation.interest, evaluation.kind == .interest {
            return [
                "Principal: \(formatted(interest.principal, currency: interest.currency, digits: 8))",
                "Annual rate: \(NumberFormatting.string(interest.annualRate * 100))%",
                "Elapsed days: \(NumberFormatting.string(interest.days))",
                "Year basis: Actual/\(NumberFormatting.string(interest.yearBasis))",
                "Gross interest: \(formatted(interest.interest, currency: interest.currency, digits: 8))",
                "Final balance: \(formatted(interest.total, currency: interest.currency, digits: 8))",
                "Simple interest, no deductions."
            ].joined(separator: "\n")
        }
        if let value = evaluation.value {
            let fullValue = NSDecimalNumber(decimal: value).stringValue + suffix(evaluation.currency)
            if let detail = evaluation.detail, !detail.isEmpty {
                return fullValue + "\n" + detail
            }
            return fullValue
        }
        return evaluation.detail ?? evaluation.title
    }

    private static func formatted(_ value: Decimal, currency: String?, digits: Int) -> String {
        NumberFormatting.string(value, maximumFractionDigits: digits) + suffix(currency)
    }

    private static func suffix(_ currency: String?) -> String {
        guard let currency else { return "" }
        let code = CurrencyPair.canonical(currency)
        return " " + (code == "TRY" ? "TL" : code)
    }
}
