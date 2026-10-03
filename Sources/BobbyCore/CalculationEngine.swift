import Foundation

public struct CurrencyPair: Hashable, Sendable {
    public let base: String
    public let quote: String

    public init(base: String, quote: String) {
        self.base = Self.canonical(base)
        self.quote = Self.canonical(quote)
    }

    public static func canonical(_ currency: String) -> String {
        let code = currency.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return code == "TL" ? "TRY" : code
    }
}

public struct ConversionRequest: Equatable, Sendable {
    public let amount: Decimal
    public let pair: CurrencyPair
    public let isRateQuery: Bool

    public init(amount: Decimal, pair: CurrencyPair, isRateQuery: Bool = false) {
        self.amount = amount
        self.pair = pair
        self.isRateQuery = isRateQuery
    }
}

public enum CalculationSuggestion: Equatable, Sendable {
    case currency(canonicalExpression: String, question: String)
    case interest(FinanceSuggestion)
}

public struct InterestDetails: Equatable, Sendable {
    public let principal: Decimal
    public let annualRate: Decimal
    public let days: Decimal
    public let yearBasis: Decimal
    public let interest: Decimal
    public let total: Decimal
    public let currency: String?

    public init(principal: Decimal, annualRate: Decimal, days: Decimal, yearBasis: Decimal,
                interest: Decimal, total: Decimal, currency: String?) {
        self.principal = principal
        self.annualRate = annualRate
        self.days = days
        self.yearBasis = yearBasis
        self.interest = interest
        self.total = total
        self.currency = currency.map(CurrencyPair.canonical)
    }
}

public struct LineEvaluation: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case value
        case interest
        case conversion
        case gold
        case suggestion
        case error
    }

    public var lineIndex: Int
    public var kind: Kind
    public var value: Decimal?
    public var currency: String?
    public var conversion: ConversionRequest?
    public var interest: InterestDetails?
    public var suggestion: CalculationSuggestion?
    public var gold: GoldRequest?
    public var title: String
    public var detail: String?

    public init(lineIndex: Int, kind: Kind, value: Decimal? = nil, currency: String? = nil,
                conversion: ConversionRequest? = nil, interest: InterestDetails? = nil,
                title: String, detail: String? = nil, suggestion: CalculationSuggestion? = nil,
                gold: GoldRequest? = nil) {
        self.lineIndex = lineIndex
        self.kind = kind
        self.value = value
        self.currency = currency.map(CurrencyPair.canonical)
        self.conversion = conversion
        self.interest = interest
        self.suggestion = suggestion
        self.gold = gold
        self.title = title
        self.detail = detail
    }
}

/// A line-by-line, network-free calculator. Each evaluation rebuilds variables in
/// source order so changes cannot leave stale values behind.
public struct CalculationEngine: Sendable {
    public init() {}

    public func evaluate(_ text: String, yearBasis: Int = 365,
                         rates: [CurrencyPair: Decimal] = [:],
                         goldQuotes: [GoldProduct: GoldQuote] = [:]) -> [LineEvaluation] {
        var variables: [String: Quantity] = [:]
        var awaitingRates: Set<String> = []
        var results: [LineEvaluation] = []

        for (lineIndex, rawLine) in text.components(separatedBy: "\n").enumerated() {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            let assignment = Self.assignment(in: line)
            let expression = assignment?.expression ?? line
            let tokens = Lexer(expression).tokens()
            var dependencyTokens = tokens
            let pendingCurrencyVariable: Bool
            if tokens.count == 2, case .identifier(let name) = tokens[0],
               case .identifier(let currency) = tokens[1], Currencies.contains(currency),
               awaitingRates.contains(name.lowercased()) {
                pendingCurrencyVariable = true
            } else { pendingCurrencyVariable = false }
            // A currency code in a conversion is a unit, not a dependency on a
            // variable with the same spelling. Only inspect the amount expression.
            if case .gold(_, let quantity, let side) = GoldInputRecognizer.recognize(expression) {
                dependencyTokens = assignment != nil && side == nil ? [] : Lexer(quantity).tokens()
            } else if !pendingCurrencyVariable, let currency = CurrencyInputRecognizer.recognize(expression) {
                switch currency {
                case .conversion(let amount, _, _): dependencyTokens = Lexer(amount).tokens()
                case .suggestion(let canonical, _):
                    if case .conversion(let amount, _, _) = CurrencyInputRecognizer.recognize(canonical) {
                        dependencyTokens = Lexer(amount).tokens()
                    }
                }
            } else if FinanceInputSuggestions.suggestion(for: expression) != nil {
                dependencyTokens = []
            }
            if dependencyTokens.contains(where: { token in
                if case .identifier(let name) = token { return awaitingRates.contains(name.lowercased()) }
                return false
            }) {
                if let assignment {
                    variables.removeValue(forKey: assignment.name.lowercased())
                    awaitingRates.insert(assignment.name.lowercased())
                }
                continue
            }
            do {
                guard var result = try evaluateLine(expression, lineIndex: lineIndex,
                                                    yearBasis: yearBasis, rates: rates, goldQuotes: goldQuotes,
                                                    variables: variables,
                                                    isAssignment: assignment != nil) else {
                    if let assignment {
                        variables.removeValue(forKey: assignment.name.lowercased())
                        awaitingRates.remove(assignment.name.lowercased())
                    }
                    continue
                }
                if let assignment {
                    if let value = result.value, result.kind != .error {
                        variables[assignment.name.lowercased()] = Quantity(value: value, currency: result.currency)
                        awaitingRates.remove(assignment.name.lowercased())
                    } else {
                        variables.removeValue(forKey: assignment.name.lowercased())
                        if result.kind == .conversion || result.kind == .suggestion || result.kind == .gold {
                            awaitingRates.insert(assignment.name.lowercased())
                        } else {
                            awaitingRates.remove(assignment.name.lowercased())
                        }
                    }
                    if result.kind == .value { result.title = assignment.name }
                }
                results.append(result)
            } catch let failure as CalculationFailure {
                if let assignment {
                    variables.removeValue(forKey: assignment.name.lowercased())
                    awaitingRates.remove(assignment.name.lowercased())
                }
                if case .invalid(let message) = failure {
                    results.append(LineEvaluation(lineIndex: lineIndex, kind: .error,
                                                  title: "Calculation error", detail: message))
                }
            } catch {
                if let assignment {
                    variables.removeValue(forKey: assignment.name.lowercased())
                    awaitingRates.remove(assignment.name.lowercased())
                }
                results.append(LineEvaluation(lineIndex: lineIndex, kind: .error,
                                              title: "Calculation error", detail: "Unable to calculate this expression."))
            }
        }
        return results
    }

    private func evaluateLine(_ text: String, lineIndex: Int, yearBasis: Int,
                              rates: [CurrencyPair: Decimal], goldQuotes: [GoldProduct: GoldQuote],
                              variables: [String: Quantity],
                              isAssignment: Bool) throws -> LineEvaluation? {
        guard !text.isEmpty else { return nil }

        if case .gold(let product, let quantityExpression, let side) = GoldInputRecognizer.recognize(text) {
            guard !isAssignment || side != nil else {
                throw CalculationFailure.invalid("Choose a gold quote side for an assignment, for example ceyrek altin buy or ceyrek altin sell (dealer prices).")
            }
            let tokens = Lexer(quantityExpression).tokens()
            guard Self.isCalculation(tokens, variables: variables, isAssignment: isAssignment) else { return nil }
            var parser = Parser(tokens: tokens, variables: variables)
            let quantity = try parser.parse()
            guard quantity.currency == nil else {
                throw CalculationFailure.invalid("Gold quantities must be plain numbers, not money amounts.")
            }
            guard quantity.value >= 0 else {
                throw CalculationFailure.invalid("Gold quantities must be zero or greater.")
            }
            let request = GoldRequest(product: product, quantity: quantity.value, side: side)
            var value: Decimal?
            if let quote = goldQuotes[product] {
                guard quote.product == product, !quote.dealerBuy.isNaN, !quote.dealerSell.isNaN,
                      quote.dealerBuy > 0, quote.dealerSell > 0, quote.dealerBuy <= quote.dealerSell else {
                    throw CalculationFailure.invalid("The gold source returned an invalid quote for this product.")
                }
                if let side {
                    value = try DecimalMath.multiply(quantity.value, side == .dealerBuy ? quote.dealerBuy : quote.dealerSell)
                }
            }
            return LineEvaluation(lineIndex: lineIndex, kind: .gold, value: value, currency: "TRY",
                                  title: product.displayName, gold: request)
        }

        if let proposal = FinanceInputSuggestions.suggestion(for: text) {
            let draft = proposal.interest
            return LineEvaluation(lineIndex: lineIndex, kind: .suggestion,
                                  title: proposal.title,
                                  detail: "\(draft.principal == nil ? "Add principal · " : "Review · ")\(NumberFormatting.string(draft.annualRatePercent))% yearly · \(draft.duration.displayText)",
                                  suggestion: .interest(proposal))
        }

        if let pieces = Self.captures(in: text, pattern:
            #"^(.+?)\s+(at)\s+(.+?)\s+for\s+(.+?)\s+days?(?:\s+basis\s+(\d+))?\s*$"#) {
            return try interestResult(principal: pieces[0], rate: pieces[2], days: pieces[3],
                                      explicitBasis: pieces[4], defaultBasis: yearBasis,
                                      lineIndex: lineIndex, variables: variables)
        }

        if let pieces = Self.captures(in: text, pattern:
            #"^(.+?)\s+(%\s*[^\s]+|[^\s]+\s*%)\s+(?:yıllık|yillik)\s+(.+?)\s+(?:gün|gun)(?:\s+basis\s+(\d+))?\s*$"#) {
            return try interestResult(principal: pieces[0], rate: pieces[1], days: pieces[2],
                                      explicitBasis: pieces[3], defaultBasis: yearBasis,
                                      lineIndex: lineIndex, variables: variables)
        }

        let tokens = Lexer(text).tokens()
        let usesBoundCurrencyVariable: Bool
        if tokens.count == 2, case .identifier(let name) = tokens[0],
           case .identifier(let currency) = tokens[1], Currencies.contains(currency), variables[name.lowercased()] != nil {
            usesBoundCurrencyVariable = true
        } else {
            usesBoundCurrencyVariable = false
        }
        if !usesBoundCurrencyVariable, let recognition = CurrencyInputRecognizer.recognize(text) {
            let amountExpression: String
            let pair: CurrencyPair
            let isRateQuery: Bool
            var suggestion: CalculationSuggestion?
            switch recognition {
            case .conversion(let expression, let recognizedPair, let rateQuery):
                amountExpression = expression
                pair = recognizedPair
                isRateQuery = rateQuery
            case .suggestion(let canonicalExpression, let question):
                guard case .conversion(let expression, let recognizedPair, let rateQuery) = CurrencyInputRecognizer.recognize(canonicalExpression) else { return nil }
                amountExpression = expression
                pair = recognizedPair
                isRateQuery = rateQuery
                suggestion = .currency(canonicalExpression: canonicalExpression, question: question)
            }
            let tokens = Lexer(amountExpression).tokens()
            guard Self.isCalculation(tokens, variables: variables, isAssignment: isAssignment) else { return nil }
            var parser = Parser(tokens: tokens, variables: variables)
            let quantity = try parser.parse()
            if let currency = quantity.currency, currency != pair.base {
                throw CalculationFailure.invalid("The amount's currency must match \(pair.base).")
            }
            if let suggestion, case .currency(let canonical, let question) = suggestion {
                return LineEvaluation(lineIndex: lineIndex, kind: .suggestion,
                                      title: question, detail: canonical, suggestion: suggestion)
            }
            let request = ConversionRequest(amount: quantity.value, pair: pair, isRateQuery: isRateQuery)
            let rate = pair.base == pair.quote ? Decimal(1) : rates[pair]
            var value: Decimal?
            if let rate {
                guard !rate.isNaN, rate > 0 else { throw CalculationFailure.invalid("The exchange rate must be positive.") }
                value = try DecimalMath.multiply(quantity.value, rate)
            }
            return LineEvaluation(lineIndex: lineIndex, kind: .conversion, value: value,
                                  currency: pair.quote, conversion: request,
                                  title: "\(pair.base) → \(pair.quote)")
        }

        // Finance phrases are only evaluated once the whole documented pattern
        // is present. Partial phrases remain quiet during normal editing.
        if text.range(of: #"(?:\byıllık\b|\byillik\b|\bat\b|\bfor\b|\s%[0-9.])"#,
                      options: [.regularExpression, .caseInsensitive]) != nil {
            return nil
        }

        guard Self.isCalculation(tokens, variables: variables, isAssignment: isAssignment) else { return nil }
        var parser = Parser(tokens: tokens, variables: variables)
        let quantity = try parser.parse()
        return LineEvaluation(lineIndex: lineIndex, kind: .value, value: quantity.value,
                              currency: quantity.currency, title: "Result")
    }

    private func interestResult(principal: String, rate: String, days: String,
                                explicitBasis: String, defaultBasis: Int,
                                lineIndex: Int, variables: [String: Quantity]) throws -> LineEvaluation {
        var principalParser = Parser(tokens: Lexer(principal).tokens(), variables: variables)
        let principalValue = try principalParser.parse()
        var normalizedRate = rate.trimmingCharacters(in: .whitespaces)
        if normalizedRate.hasPrefix("%") {
            normalizedRate.removeFirst()
            normalizedRate = normalizedRate.trimmingCharacters(in: .whitespaces) + "%"
        }
        guard normalizedRate.hasSuffix("%") else {
            throw CalculationFailure.invalid("Write the annual rate as a percentage, for example 40%.")
        }
        var rateParser = Parser(tokens: Lexer(normalizedRate).tokens(), variables: variables)
        let rateValue = try rateParser.parse()
        var daysParser = Parser(tokens: Lexer(days).tokens(), variables: variables)
        let dayValue = try daysParser.parse()
        guard rateValue.currency == nil, dayValue.currency == nil else {
            throw CalculationFailure.invalid("Rates and days must be plain numbers.")
        }
        guard principalValue.value >= 0, dayValue.value >= 0 else {
            throw CalculationFailure.invalid("Principal and elapsed days must be zero or greater.")
        }
        let basis = explicitBasis.isEmpty ? Decimal(defaultBasis) : Decimal(string: explicitBasis)
        guard let basis, basis > 0 else {
            throw CalculationFailure.invalid("The interest year basis must be greater than zero.")
        }
        let accrued = try DecimalMath.divide(
            DecimalMath.multiply(DecimalMath.multiply(principalValue.value, rateValue.value), dayValue.value), basis)
        let total = try DecimalMath.add(principalValue.value, accrued)
        let details = InterestDetails(principal: principalValue.value, annualRate: rateValue.value,
                                      days: dayValue.value, yearBasis: basis, interest: accrued,
                                      total: total, currency: principalValue.currency)
        let currencySuffix = principalValue.currency.map { " \($0)" } ?? ""
        return LineEvaluation(lineIndex: lineIndex, kind: .interest, value: accrued,
                              currency: principalValue.currency, interest: details,
                              title: "Simple interest",
                              detail: "Total: \(NumberFormatting.string(total))\(currencySuffix) · Actual/\(NumberFormatting.string(basis))")
    }

    private static func assignment(in text: String) -> (name: String, expression: String)? {
        guard let pieces = captures(in: text, pattern: #"^([\p{L}_][\p{L}\p{N}_]*)\s*=\s*(.*)$"#) else { return nil }
        return (pieces[0], pieces[1])
    }

    private static func captures(in text: String, pattern: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        return (1..<match.numberOfRanges).map { index in
            guard let range = Range(match.range(at: index), in: text) else { return "" }
            return String(text[range])
        }
    }

    private static func isCalculation(_ tokens: [Token], variables: [String: Quantity], isAssignment: Bool) -> Bool {
        guard !tokens.isEmpty, !tokens.contains(where: { if case .unknown = $0 { return true }; return false }) else { return false }
        if tokens.count == 1, case .identifier(let name) = tokens[0], variables[name.lowercased()] == nil { return false }
        let unknownNames = tokens.compactMap { token -> String? in
            guard case .identifier(let name) = token,
                  variables[name.lowercased()] == nil, !Currencies.contains(name) else { return nil }
            return name
        }
        if unknownNames.isEmpty { return true }
        // A number followed by prose, or several words in a row, is a note.
        // A misspelled variable in `amount * 2` is still a useful error.
        for pair in zip(tokens, tokens.dropFirst()) {
            guard case .identifier(let name) = pair.1,
                  variables[name.lowercased()] == nil, !Currencies.contains(name) else { continue }
            switch pair.0 {
            case .number, .identifier, .rightParen: return false
            default: break
            }
        }
        let hasOperator = tokens.contains { token in
            switch token {
            case .plus, .minus, .multiply, .divide, .power, .percent, .leftParen, .rightParen: return true
            default: return false
            }
        }
        let hasOperand = tokens.contains { token in
            switch token {
            case .number, .invalidNumber, .incompleteNumber: return true
            case .identifier(let name): return variables[name.lowercased()] != nil
            default: return false
            }
        }
        return hasOperator && (hasOperand || isAssignment)
    }
}

private struct Quantity {
    let value: Decimal
    let currency: String?

    init(value: Decimal, currency: String? = nil) {
        self.value = value
        self.currency = currency.map(CurrencyPair.canonical)
    }
}

private enum CalculationFailure: Error {
    case incomplete
    case invalid(String)
}

private enum Currencies {
    static let codes: Set<String> = [
        "AED", "AUD", "AZN", "BGN", "BHD", "BRL", "CAD", "CHF", "CNY", "CZK", "DKK", "EGP",
        "EUR", "GBP", "GEL", "HKD", "HUF", "IDR", "ILS", "INR", "ISK", "JPY", "KRW", "KWD",
        "KZT", "MXN", "MYR", "NOK", "NZD", "PHP", "PLN", "QAR", "RON", "RUB", "SAR", "SEK",
        "SGD", "THB", "TRY", "TWD", "UAH", "USD", "VND", "ZAR"
    ]

    static func contains(_ text: String) -> Bool { codes.contains(CurrencyPair.canonical(text)) }
}

private enum Token {
    case number(Decimal)
    case invalidNumber(String)
    case incompleteNumber
    case identifier(String)
    case plus, minus, multiply, divide, power, percent, leftParen, rightParen
    case unknown(String)
}

private struct Lexer {
    let characters: [Character]

    init(_ text: String) { characters = Array(text) }

    func tokens() -> [Token] {
        var result: [Token] = []
        var index = 0
        while index < characters.count {
            let character = characters[index]
            if character.isWhitespace { index += 1; continue }
            if character.isASCII && character.isNumber || character == "." {
                let start = index
                while index < characters.count {
                    let current = characters[index]
                    guard current.isASCII && current.isNumber || current == "." || current == "," else { break }
                    index += 1
                }
                let literal = String(characters[start..<index])
                var multiplier = Decimal(1)
                if index < characters.count, "kKmM".contains(characters[index]),
                   index + 1 == characters.count || (!characters[index + 1].isLetter && !characters[index + 1].isNumber && characters[index + 1] != "_") {
                    multiplier = characters[index].lowercased() == "k" ? Decimal(1_000) : Decimal(1_000_000)
                    index += 1
                }
                if literal == "." || (literal.hasSuffix(".") && Self.validNumber(String(literal.dropLast()))) {
                    result.append(.incompleteNumber)
                } else if Self.validNumber(literal),
                          let value = Decimal(string: literal.replacingOccurrences(of: ",", with: ""), locale: Locale(identifier: "en_US_POSIX")),
                          let scaled = try? DecimalMath.multiply(value, multiplier) {
                    result.append(.number(scaled))
                } else {
                    result.append(.invalidNumber(literal))
                }
                continue
            }
            if character.isLetter || character == "_" {
                let start = index
                index += 1
                while index < characters.count, characters[index].isLetter || characters[index].isNumber || characters[index] == "_" { index += 1 }
                result.append(.identifier(String(characters[start..<index])))
                continue
            }
            switch character {
            case "+": result.append(.plus)
            case "-", "−": result.append(.minus)
            case "*", "×": result.append(.multiply)
            case "/", "÷": result.append(.divide)
            case "^": result.append(.power)
            case "%": result.append(.percent)
            case "(": result.append(.leftParen)
            case ")": result.append(.rightParen)
            default: result.append(.unknown(String(character)))
            }
            index += 1
        }
        return result
    }

    private static func validNumber(_ text: String) -> Bool {
        text.range(of: #"^(?:(?:[0-9]+|[0-9]{1,3}(?:,[0-9]{3})+)(?:\.[0-9]+)?|\.[0-9]+)$"#,
                   options: .regularExpression) != nil
    }
}

private struct Parser {
    let tokens: [Token]
    let variables: [String: Quantity]
    private var index = 0

    init(tokens: [Token], variables: [String: Quantity]) {
        self.tokens = tokens
        self.variables = variables
    }

    mutating func parse() throws -> Quantity {
        guard !tokens.isEmpty else { throw CalculationFailure.incomplete }
        guard tokens.count <= 512 else { throw CalculationFailure.invalid("This expression is too long. Split it into smaller calculations.") }
        let result = try addition()
        guard index == tokens.count else {
            throw CalculationFailure.invalid("Use an operator between values and English number formatting (1,234.56).")
        }
        return result
    }

    private mutating func addition() throws -> Quantity {
        var left = try multiplication()
        while index < tokens.count {
            let add: Bool
            switch tokens[index] {
            case .plus: add = true
            case .minus: add = false
            default: return left
            }
            index += 1
            let right = try multiplication()
            guard left.currency == right.currency else {
                throw CalculationFailure.invalid("Add or subtract amounts in the same currency. Convert them first.")
            }
            left = Quantity(value: try add ? DecimalMath.add(left.value, right.value) : DecimalMath.subtract(left.value, right.value), currency: left.currency)
        }
        return left
    }

    private mutating func multiplication() throws -> Quantity {
        var left = try unary()
        while index < tokens.count {
            let multiply: Bool
            switch tokens[index] {
            case .multiply: multiply = true
            case .divide: multiply = false
            default: return left
            }
            index += 1
            let right = try unary()
            if multiply {
                guard left.currency == nil || right.currency == nil else {
                    throw CalculationFailure.invalid("Multiply a money amount by a plain number or percentage.")
                }
                left = Quantity(value: try DecimalMath.multiply(left.value, right.value), currency: left.currency ?? right.currency)
            } else {
                let currency: String?
                if right.currency == nil {
                    currency = left.currency
                } else if left.currency == right.currency {
                    currency = nil
                } else {
                    throw CalculationFailure.invalid("Divide by a plain number or an amount in the same currency.")
                }
                left = Quantity(value: try DecimalMath.divide(left.value, right.value), currency: currency)
            }
        }
        return left
    }

    private mutating func unary() throws -> Quantity {
        guard index < tokens.count else { throw CalculationFailure.incomplete }
        switch tokens[index] {
        case .plus:
            index += 1
            return try unary()
        case .minus:
            index += 1
            let quantity = try unary()
            return Quantity(value: try DecimalMath.subtract(0, quantity.value), currency: quantity.currency)
        default:
            return try power()
        }
    }

    private mutating func power() throws -> Quantity {
        let left = try postfix()
        if index < tokens.count, case .power = tokens[index] {
            index += 1
            let right = try unary()
            guard right.currency == nil else { throw CalculationFailure.invalid("An exponent must be a plain integer.") }
            guard right.value >= -100, right.value <= 100 else {
                throw CalculationFailure.invalid("Use an integer exponent between -100 and 100.")
            }
            let exponent = NSDecimalNumber(decimal: right.value).intValue
            guard right.value == Decimal(exponent) else { throw CalculationFailure.invalid("Only integer exponents are supported.") }
            guard left.currency == nil || exponent == 0 || exponent == 1 else {
                throw CalculationFailure.invalid("A money amount can only use powers of zero or one.")
            }
            return Quantity(value: try DecimalMath.power(left.value, exponent), currency: exponent == 0 ? nil : left.currency)
        }
        return left
    }

    private mutating func postfix() throws -> Quantity {
        var result = try primary()
        while index < tokens.count, case .percent = tokens[index] {
            index += 1
            result = Quantity(value: try DecimalMath.divide(result.value, 100), currency: result.currency)
        }
        if index < tokens.count, case .identifier(let code) = tokens[index], Currencies.contains(code) {
            guard result.currency == nil || result.currency == CurrencyPair.canonical(code) else {
                throw CalculationFailure.invalid("The amount already has a different currency.")
            }
            index += 1
            result = Quantity(value: result.value, currency: code)
        }
        return result
    }

    private mutating func primary() throws -> Quantity {
        guard index < tokens.count else { throw CalculationFailure.incomplete }
        let token = tokens[index]
        index += 1
        switch token {
        case .number(let value):
            return Quantity(value: value)
        case .identifier(let name):
            guard let value = variables[name.lowercased()] else {
                throw CalculationFailure.invalid("Unknown variable: \(name). Define it on a line above.")
            }
            return value
        case .leftParen:
            let value = try addition()
            guard index < tokens.count else { throw CalculationFailure.incomplete }
            guard case .rightParen = tokens[index] else { throw CalculationFailure.invalid("Close the parenthesis before continuing.") }
            index += 1
            return value
        case .incompleteNumber:
            throw CalculationFailure.incomplete
        case .invalidNumber(let literal):
            throw CalculationFailure.invalid("Invalid number '\(literal)'. Use English formatting, such as 1,234.56.")
        default:
            throw CalculationFailure.invalid("Expected a number, variable, or parenthesis.")
        }
    }
}

private enum DecimalMath {
    static func add(_ lhs: Decimal, _ rhs: Decimal) throws -> Decimal {
        try calculate(lhs, rhs, operation: NSDecimalAdd)
    }

    static func subtract(_ lhs: Decimal, _ rhs: Decimal) throws -> Decimal {
        try calculate(lhs, rhs, operation: NSDecimalSubtract)
    }

    static func multiply(_ lhs: Decimal, _ rhs: Decimal) throws -> Decimal {
        do { return try CheckedDecimalMath.multiply(lhs, rhs) }
        catch { throw CalculationFailure.invalid("The result is outside the supported decimal range.") }
    }

    static func divide(_ lhs: Decimal, _ rhs: Decimal) throws -> Decimal {
        guard rhs != 0 else { throw CalculationFailure.invalid("Cannot divide by zero.") }
        do { return try CheckedDecimalMath.divide(lhs, rhs) }
        catch { throw CalculationFailure.invalid("The result is outside the supported decimal range.") }
    }

    static func power(_ value: Decimal, _ exponent: Int) throws -> Decimal {
        guard exponent < 0 else { return try positivePower(value, exponent) }
        guard value != 0 else { throw CalculationFailure.invalid("Cannot divide by zero.") }
        do {
            // Retain the ordinary path so recurring reciprocals are rounded only
            // after exponentiation, rather than once per intermediate product.
            return try divide(1, positivePower(value, -exponent))
        } catch {
            // The positive power can underflow even when its reciprocal is
            // representable, for example .01^-65 = 1e130.
            return try positivePower(divide(1, value), -exponent)
        }
    }

    private static func positivePower(_ value: Decimal, _ exponent: Int) throws -> Decimal {
        var result = Decimal(1)
        var factor = value
        var remaining = exponent
        while remaining > 0 {
            if remaining % 2 == 1 { result = try multiply(result, factor) }
            remaining /= 2
            if remaining > 0 { factor = try multiply(factor, factor) }
        }
        return result
    }

    private static func calculate(_ lhs: Decimal, _ rhs: Decimal,
                                  operation: (UnsafeMutablePointer<Decimal>, UnsafePointer<Decimal>, UnsafePointer<Decimal>, Decimal.RoundingMode) -> Decimal.CalculationError) throws -> Decimal {
        var lhs = lhs
        var rhs = rhs
        var result = Decimal()
        let status = operation(&result, &lhs, &rhs, .plain)
        switch status {
        case .noError, .lossOfPrecision:
            guard !result.isNaN else { throw CalculationFailure.invalid("The result is outside the supported decimal range.") }
            return result
        case .divideByZero:
            throw CalculationFailure.invalid("Cannot divide by zero.")
        case .overflow, .underflow:
            throw CalculationFailure.invalid("The result is outside the supported decimal range.")
        @unknown default:
            throw CalculationFailure.invalid("Unable to calculate this expression.")
        }
    }
}
