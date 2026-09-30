import AppKit
import BobbyCore
import Combine
import Foundation

struct DisplayResult: Equatable {
    let lineIndex: Int
    let text: String
    let detail: String
    let tooltip: String
    let isError: Bool
    let copyText: String?
}

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var collection: ScratchCollection
    @Published private(set) var results: [DisplayResult] = []
    @Published private(set) var saveMessage = "Saved on this Mac"
    @Published private(set) var errorMessage: String?
    @Published var isPinned = false
    @Published var showHelp = false
    @Published var showSettings = false
    @Published var shortcutChoice: String {
        didSet { UserDefaults.standard.set(shortcutChoice, forKey: "globalShortcut") }
    }
    @Published var shortcutError: String?
    @Published private(set) var feedback: String?
    var selectedLine = 0

    private let store: ScratchStore
    private let rates: ExchangeRateStore
    private let engine = CalculationEngine()
    private var quotes: [CurrencyPair: RateLookup] = [:]
    private var rateErrors: [CurrencyPair: String] = [:]
    private var requests: [CurrencyPair: Task<Void, Never>] = [:]
    private var saveTask: Task<Void, Never>?
    private var feedbackTask: Task<Void, Never>?
    private var persistenceEnabled = true

    static let welcome = """
    A little room for your numbers.

    11.5m * 2%
    500 USD to TL

    principal = 500k
    interest = 500k TL %40 yıllık 32 gün
    interest * .75
    """

    init() {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Bobby", isDirectory: true)
        store = ScratchStore(fileURL: directory.appendingPathComponent("scratches.json"))
        rates = ExchangeRateStore(cacheURL: directory.appendingPathComponent("exchange-rates.json"))
        shortcutChoice = UserDefaults.standard.string(forKey: "globalShortcut") ?? "controlOptionB"
        let scratch = Scratch(text: Self.welcome)
        collection = ScratchCollection(scratches: [scratch], selectedID: scratch.id, yearBasis: 365)
        do {
            if let saved = try store.load() {
                collection = saved
                if collection.scratches.isEmpty {
                    let blank = Scratch(text: "")
                    collection.scratches = [blank]
                    collection.selectedID = blank.id
                }
            }
        } catch {
            persistenceEnabled = false
            errorMessage = "Your saved scratches could not be read. The original file is preserved. Export any new work before quitting."
            saveMessage = "Saving paused"
        }
        recalculate()
        if persistenceEnabled { scheduleSave() }
    }

    var currentText: String {
        collection.scratches.first(where: { $0.id == collection.selectedID })?.text ?? ""
    }

    var currentTitle: String {
        title(for: collection.scratches.first(where: { $0.id == collection.selectedID }))
    }

    func title(for scratch: Scratch?) -> String {
        guard let scratch else { return "Scratch" }
        let first = scratch.text.components(separatedBy: .newlines)
            .first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) ?? "New scratch"
        return String(first.prefix(32))
    }

    func updateText(_ text: String) {
        guard let index = collection.scratches.firstIndex(where: { $0.id == collection.selectedID }) else { return }
        collection.scratches[index].text = text
        collection.scratches[index].updatedAt = Date()
        recalculate()
        scheduleSave()
    }

    func select(_ id: UUID) {
        guard collection.scratches.contains(where: { $0.id == id }) else { return }
        flushSave()
        collection.selectedID = id
        selectedLine = 0
        recalculate()
        scheduleSave()
    }

    func newScratch() {
        flushSave()
        let scratch = Scratch(text: "")
        collection.scratches.append(scratch)
        collection.selectedID = scratch.id
        recalculate()
        scheduleSave()
    }

    func navigate(_ offset: Int) {
        guard let index = collection.scratches.firstIndex(where: { $0.id == collection.selectedID }) else { return }
        let target = min(max(0, index + offset), collection.scratches.count - 1)
        select(collection.scratches[target].id)
    }

    func deleteCurrent() {
        guard let id = collection.selectedID else { return }
        let alert = NSAlert()
        alert.messageText = "Delete this scratch?"
        alert.informativeText = "This removes \"\(currentTitle)\" from this Mac."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let index = collection.scratches.firstIndex(where: { $0.id == id }) ?? 0
        collection.scratches.removeAll(where: { $0.id == id })
        if collection.scratches.isEmpty {
            collection.scratches = [Scratch(text: "")]
        }
        collection.selectedID = collection.scratches[min(index, collection.scratches.count - 1)].id
        recalculate()
        scheduleSave()
    }

    func setYearBasis(_ basis: Int) {
        guard [360, 365, 366].contains(basis) else { return }
        collection.yearBasis = basis
        recalculate()
        scheduleSave()
    }

    func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        feedback = "Copied"
        feedbackTask?.cancel()
        feedbackTask = Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled else { return }
            feedback = nil
        }
    }

    func copyCurrentResult() {
        if let text = results.first(where: { $0.lineIndex == selectedLine })?.copyText { copy(text) }
        else { feedback = "No answer on this line" }
    }

    func exportScratch(markdown: Bool = false) {
        let panel = NSSavePanel()
        let filename = currentTitle.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        panel.nameFieldStringValue = "\(filename).\(markdown ? "md" : "txt")"
        panel.title = "Save this scratch"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try currentText.write(to: url, atomically: true, encoding: .utf8) }
        catch { errorMessage = "Could not export this scratch: \(error.localizedDescription)" }
    }

    func refreshRates(force: Bool = true) {
        rateErrors = [:]
        let pairs = Set(engine.evaluate(currentText, yearBasis: collection.yearBasis,
                                       rates: quotes.mapValues { $0.quote.rate }).compactMap { $0.conversion?.pair })
        for pair in pairs { request(pair, force: force) }
        recalculate()
    }

    func flushSave() {
        saveTask?.cancel()
        guard persistenceEnabled else { return }
        do {
            try store.save(collection)
            saveMessage = "Saved on this Mac"
        } catch {
            saveMessage = "Could not save"
            errorMessage = "Could not save your scratch: \(error.localizedDescription). You can export it to keep a copy."
        }
    }

    func dismissError() { errorMessage = nil }

    private func scheduleSave() {
        guard persistenceEnabled else { return }
        saveTask?.cancel()
        saveMessage = "Saving…"
        saveTask = Task {
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            flushSave()
        }
    }

    private func recalculate() {
        let evaluations = engine.evaluate(currentText, yearBasis: collection.yearBasis,
                                          rates: quotes.mapValues { $0.quote.rate })
        results = evaluations.map { evaluation in
            if let conversion = evaluation.conversion {
                let pair = conversion.pair
                if let lookup = quotes[pair] {
                    var amount = conversion.amount
                    var rate = lookup.quote.rate
                    var value = Decimal()
                    let calculation = NSDecimalMultiply(&value, &amount, &rate, .bankers)
                    guard calculation == .noError || calculation == .lossOfPrecision, !value.isNaN else {
                        return DisplayResult(lineIndex: evaluation.lineIndex, text: "Amount too large", detail: "",
                                             tooltip: "The converted amount exceeds Decimal precision.", isError: true, copyText: nil)
                    }
                    let currency = pair.quote == "TRY" ? "TL" : pair.quote
                    let text = "\(NumberFormatting.string(value, maximumFractionDigits: 2)) \(currency)"
                    let date = lookup.quote.observedDate
                    let cache = lookup.usedOfflineCache ? " · offline cache" : ""
                    let detail = "\(date)\(cache)\(requests[pair] == nil ? "" : " · refreshing")"
                    let tooltip = "1 \(pair.base) = \(NumberFormatting.string(rate)) \(currency)\n\(lookup.quote.sourceLabel)\n\(lookup.quote.rateType)\nRate date: \(date)\(cache)"
                    return DisplayResult(lineIndex: evaluation.lineIndex, text: text, detail: detail,
                                         tooltip: tooltip, isError: false, copyText: text)
                }
                if let error = rateErrors[pair] {
                    return DisplayResult(lineIndex: evaluation.lineIndex, text: "Rate unavailable", detail: "Refresh to retry",
                                         tooltip: error, isError: true, copyText: nil)
                }
                request(pair)
                return DisplayResult(lineIndex: evaluation.lineIndex, text: "Getting rate…", detail: "\(pair.base) → \(pair.quote)",
                                     tooltip: "Fetching a dated reference rate.", isError: false, copyText: nil)
            }
            let error = evaluation.kind == .error
            let text = CalculationPresentation.valueText(evaluation)
            return DisplayResult(lineIndex: evaluation.lineIndex, text: text, detail: CalculationPresentation.detail(evaluation),
                                 tooltip: CalculationPresentation.tooltip(evaluation),
                                 isError: error, copyText: error ? nil : text)
        }
    }

    private func request(_ pair: CurrencyPair, force: Bool = false) {
        if requests[pair] != nil { return }
        requests[pair] = Task {
            do {
                let lookup = try await rates.lookup(for: pair, forceRefresh: force)
                guard !Task.isCancelled else { return }
                quotes[pair] = lookup
                rateErrors[pair] = nil
            } catch {
                rateErrors[pair] = error.localizedDescription
            }
            requests[pair] = nil
            recalculate()
        }
    }
}
