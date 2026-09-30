import BobbyCore
import SwiftUI

struct InterestReviewView: View {
    let draft: InterestDraft
    let originalLine: String
    let onCancel: () -> Void
    let onAccept: (String) -> Void
    @State private var principal: String
    @State private var currency: String
    @State private var yearBasis: Int
    @FocusState private var principalFocused: Bool

    init(draft: InterestDraft, originalLine: String, initialYearBasis: Int,
         onCancel: @escaping () -> Void, onAccept: @escaping (String) -> Void) {
        self.draft = draft
        self.originalLine = originalLine
        self.onCancel = onCancel
        self.onAccept = onAccept
        _principal = State(initialValue: draft.principal.map { NSDecimalNumber(decimal: $0).stringValue } ?? "")
        _currency = State(initialValue: draft.currency.map { $0 == "TRY" ? "TL" : $0 } ?? "")
        _yearBasis = State(initialValue: initialYearBasis)
    }

    private var reviewedExpression: String? {
        try? InterestReviewInput.expression(draft: draft, principalText: principal,
                                           currencyText: currency, yearBasis: yearBasis)
    }

    private var preview: LineEvaluation? {
        guard let expression = reviewedExpression else { return nil }
        return CalculationEngine().evaluate(expression).first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Do you mean simple interest?").font(.title2.weight(.semibold))
            Text(originalLine).font(.system(.callout, design: .monospaced)).foregroundStyle(.secondary)
                .lineLimit(2).textSelection(.enabled)
            Text(draft.reviewDetail(yearBasis: yearBasis))
                .font(.callout).fixedSize(horizontal: false, vertical: true)
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
                GridRow {
                    Text("Principal")
                    TextField("For example, 500k", text: $principal)
                        .focused($principalFocused).accessibilityIdentifier("interest-principal")
                }
                GridRow {
                    Text("Currency")
                    TextField("Optional, e.g. TL", text: $currency)
                        .accessibilityIdentifier("interest-currency")
                }
                GridRow {
                    Text("Year basis")
                    Picker("Year basis", selection: $yearBasis) {
                        ForEach([360, 365, 366], id: \.self) { Text("\($0) days").tag($0) }
                    }.labelsHidden()
                }
            }
            .textFieldStyle(.roundedBorder)
            if let preview, preview.kind == .interest {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Gross interest: " + CalculationPresentation.valueText(preview))
                        .font(.system(.body, design: .monospaced).weight(.semibold)).foregroundStyle(.teal)
                    Text(CalculationPresentation.detail(preview)).font(.caption).foregroundStyle(.secondary)
                }
            } else {
                Text(validationMessage).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("The confirmed line includes the year basis. It stays fixed if you later change the scratch setting.")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Cancel", action: onCancel).keyboardShortcut(.cancelAction)
                Spacer()
                Button("Use calculation") {
                    if let reviewedExpression { onAccept(reviewedExpression) }
                }
                .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                .disabled(preview?.kind != .interest)
                .accessibilityIdentifier("confirm-interest")
            }
        }
        .padding(28).frame(width: 510)
        .tint(.teal)
        .onAppear { principalFocused = true }
    }

    private var validationMessage: String {
        if principal.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Enter a principal to see the result. Bobby will not assume an amount."
        }
        if let preview, preview.kind == .error { return preview.detail ?? "Check the calculation." }
        return "Use a principal zero or greater (English numbers), and a currency code or full name such as Turkish lira."
    }
}
