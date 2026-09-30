import Foundation

/// Validates the review fields independently from native UI behavior. The
/// principal is one scalar arithmetic expression, never notes or assignments.
public enum InterestReviewInput {
    public static func expression(draft: InterestDraft, principalText: String,
                                  currencyText: String, yearBasis: Int) throws -> String {
        guard principalText.rangeOfCharacter(from: .newlines) == nil,
              !principalText.contains("=") else { throw InterestDraftError.invalidPrincipal }
        let principal = principalText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !principal.isEmpty else { throw InterestDraftError.missingPrincipal }
        let results = CalculationEngine().evaluate(principal)
        guard results.count == 1, let amount = results.first, amount.kind == .value,
              amount.currency == nil, let value = amount.value, !value.isNaN, value >= 0 else {
            throw InterestDraftError.invalidPrincipal
        }

        guard currencyText.rangeOfCharacter(from: .newlines) == nil else {
            throw InterestDraftError.unsupportedCurrency
        }
        let currency = currencyText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !currency.isEmpty, CurrencyInputRecognizer.canonicalCode(for: currency) == nil {
            throw InterestDraftError.unsupportedCurrency
        }
        // Passing an explicit empty string clears the draft's original currency.
        // A nil override would retain it, contrary to what the empty field shows.
        return try draft.canonicalExpression(principal: value, currency: currency, yearBasis: yearBasis)
    }
}
