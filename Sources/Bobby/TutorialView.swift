import AppKit
import SwiftUI

struct TutorialView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var step = TutorialStep.math
    @State private var demoText = TutorialStep.math.example
    @State private var demoID = UUID()
    @State private var yearBasis = 365
    @State private var selectedLine = 0
    @State private var copiedAnswer = false

    private var demoResults: [DisplayResult] {
        model.previewResults(for: demoText, yearBasis: yearBasis)
    }

    private var selectedAnswer: String? {
        demoResults.first(where: { $0.lineIndex == selectedLine })?.copyText
    }

    private var globalShortcut: String {
        GlobalShortcut.choices.first(where: { $0.id == model.shortcutChoice })?.label ?? "⌃⌥B"
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            VStack(alignment: .leading, spacing: 18) {
                progress
                introduction
                if step.hasDemo {
                    practiceScratch
                } else if step == .scratches {
                    scratchFeatures
                } else {
                    shortcutReference
                }
                tip
            }
            .padding(.horizontal, 26)
            .padding(.top, 20)
            .padding(.bottom, 18)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            Divider()
            navigation
        }
        .frame(width: 800, height: 600)
        .background(Color(nsColor: .windowBackgroundColor))
        .tint(.teal)
        .onAppear { prepareRates() }
        .onChange(of: demoText) { _, _ in
            copiedAnswer = false
            prepareRates()
        }
        .onChange(of: yearBasis) { _, _ in prepareRates() }
        .onChange(of: demoResults) { _, _ in prepareRates() }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("BobbyCopyTutorialAnswer"))) { _ in
            if step.hasDemo, let selectedAnswer { copyDemoAnswer(selectedAnswer) }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(.teal)
                .frame(width: 42, height: 42)
                .background(Color.teal.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 3) {
                Text("Meet Bobby").font(.system(size: 20, weight: .semibold, design: .rounded))
                Text("A quick tour, with room to try things.").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button { dismiss() } label: {
                Label("Close", systemImage: "xmark")
                    .font(.system(size: 12, weight: .medium))
                    .frame(minWidth: 62, minHeight: 24)
            }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .frame(minHeight: 32)
                .help("Close tutorial")
                .accessibilityLabel("Close tutorial")
                .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 16)
    }

    private var progress: some View {
        HStack(spacing: 8) {
            ForEach(TutorialStep.allCases) { lesson in
                Button { select(lesson) } label: {
                    VStack(alignment: .leading, spacing: 7) {
                        Capsule()
                            .fill(lesson.rawValue <= step.rawValue ? Color.teal : Color.secondary.opacity(0.2))
                            .frame(height: 3)
                        Text("\(lesson.rawValue + 1)  \(lesson.shortTitle)")
                            .font(.system(size: 11, weight: lesson == step ? .semibold : .regular))
                            .foregroundStyle(lesson == step ? Color.primary : Color.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Step \(lesson.rawValue + 1) of 6, \(lesson.shortTitle)")
                .accessibilityAddTraits(lesson == step ? .isSelected : [])
            }
        }
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(step.title).font(.system(size: 24, weight: .semibold, design: .rounded))
            Text(step.description)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var practiceScratch: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Label("Practice scratch", systemImage: "pencil.line")
                    .font(.system(size: 12, weight: .medium))
                if step == .interest {
                    Spacer()
                    Picker("Practice year basis", selection: $yearBasis) {
                        ForEach([360, 365, 366], id: \.self) { Text("\($0)-day year").tag($0) }
                    }
                    .labelsHidden()
                    .frame(width: 125)
                    .controlSize(.small)
                } else {
                    Spacer()
                }
                if step == .currency {
                    Button("Refresh rates") {
                        model.preparePreviewRates(for: demoText, yearBasis: yearBasis, forceRefresh: true)
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                }
                Button("Reset example") { resetExample() }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .disabled(demoText == step.example && yearBasis == 365)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color(nsColor: .controlBackgroundColor))
            Divider()
            HStack(spacing: 0) {
                Text("EDIT THE EXAMPLE")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("LIVE ANSWERS")
                    .frame(width: 218, alignment: .leading)
            }
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 28)
            .padding(.top, 12)
            ScratchEditor(text: $demoText, scratchID: demoID, results: demoResults,
                          onCopy: copyDemoAnswer, onSelection: { selectedLine = $0 },
                          onHide: { dismiss() }, yearBasis: yearBasis)
                .accessibilityLabel("Tutorial practice scratch")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            HStack(spacing: 12) {
                Text(copiedAnswer ? "Answer copied" : "A separate space to experiment.")
                    .font(.caption)
                    .foregroundStyle(copiedAnswer ? Color.teal : Color.secondary)
                Spacer()
                Button("Copy selected answer") {
                    if let selectedAnswer { copyDemoAnswer(selectedAnswer) }
                }
                .buttonStyle(.borderless)
                .font(.caption)
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(selectedAnswer == nil)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
        }
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color(nsColor: .separatorColor).opacity(0.65)))
        .frame(maxHeight: .infinity)
    }

    private var scratchFeatures: some View {
        VStack(spacing: 12) {
            featureRow(icon: "square.stack", title: "A fresh scratch for each thought",
                       detail: "Use + or ⌘N. Choose a scratch in the sidebar, use the arrows, or swipe left and right with two fingers over the editor.")
            featureRow(icon: "internaldrive", title: "Saved on this Mac",
                       detail: "Bobby saves as you write. Your scratches return when you reopen the app, and stay in place when you hide it.")
            featureRow(icon: "doc.on.doc", title: "Take an answer with you",
                       detail: "Click a live answer to copy it. Hover over it to see the calculation details, including interest assumptions and rate dates.")
            featureRow(icon: "square.and.arrow.up", title: "Keep a copy of the whole page",
                       detail: "Open the ••• menu to copy a scratch or export your source text as a text or Markdown file.")
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func featureRow(icon: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 19))
                .foregroundStyle(.teal)
                .frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
    }

    private var shortcutReference: some View {
        VStack(spacing: 0) {
            shortcutRow(globalShortcut, "Show or hide Bobby from any app", first: true)
            shortcutRow("⌘N", "Create a new scratch")
            shortcutRow("⌘⇧C", "Copy the answer on the current line")
            shortcutRow("⌘⌥←  /  ⌘⌥→", "Go to the previous or next scratch")
            shortcutRow("Esc", "Hide Bobby and keep your work")
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "slider.horizontal.3").foregroundStyle(.teal)
                Text("Change the global shortcut in Settings. Use the pin button to keep Bobby above your other windows.")
                    .font(.system(size: 12)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(16)
            .background(Color.teal.opacity(0.06))
        }
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color(nsColor: .separatorColor).opacity(0.65)))
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func shortcutRow(_ keys: String, _ action: String, first: Bool = false) -> some View {
        VStack(spacing: 0) {
            if !first { Divider().padding(.horizontal, 16) }
            HStack(spacing: 20) {
                Text(keys)
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .frame(width: 178, alignment: .leading)
                Text(action).font(.system(size: 13))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
    }

    private var tip: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "lightbulb").foregroundStyle(.teal)
            Text(step.tip)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private var navigation: some View {
        HStack(spacing: 12) {
            Text("\(step.rawValue + 1) of \(TutorialStep.allCases.count)")
                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            Spacer()
            Button("Back") {
                if let previous = TutorialStep(rawValue: step.rawValue - 1) { select(previous) }
            }
            .disabled(step == .math)
            Button(step == .shortcuts ? "Start using Bobby" : "Next") {
                if let next = TutorialStep(rawValue: step.rawValue + 1) { select(next) }
                else { dismiss() }
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 26)
        .padding(.vertical, 16)
    }

    private func select(_ lesson: TutorialStep) {
        guard lesson != step else { return }
        step = lesson
        resetExample()
    }

    private func resetExample() {
        demoText = step.example
        demoID = UUID()
        yearBasis = 365
        selectedLine = 0
        copiedAnswer = false
        prepareRates()
    }

    private func prepareRates() {
        if step.hasDemo { model.preparePreviewRates(for: demoText, yearBasis: yearBasis) }
    }

    private func copyDemoAnswer(_ answer: String) {
        model.copy(answer)
        copiedAnswer = true
    }
}

private enum TutorialStep: Int, CaseIterable, Identifiable {
    case math, variables, currency, interest, scratches, shortcuts

    var id: Int { rawValue }
    var hasDemo: Bool { rawValue < TutorialStep.scratches.rawValue }

    var shortTitle: String {
        switch self {
        case .math: return "Maths"
        case .variables: return "Variables"
        case .currency: return "Currency"
        case .interest: return "Interest"
        case .scratches: return "Scratches"
        case .shortcuts: return "Shortcuts"
        }
    }

    var title: String {
        switch self {
        case .math: return "Think on the page. Bobby does the maths."
        case .variables: return "Name a number, then build on it."
        case .currency: return "From dollars to TL, in one line."
        case .interest: return "A small space for finance calculations."
        case .scratches: return "Keep your thoughts within reach."
        case .shortcuts: return "Bobby is a shortcut away."
        }
    }

    var description: String {
        switch self {
        case .math:
            return "Write a calculation and the answer appears alongside it. Try changing a number below. Ordinary notes can share the same page."
        case .variables:
            return "Use = to give a value a name. Lines below it update when that value changes. Try changing rent from 25k to 30k."
        case .currency:
            return "Write a currency pair for its rate, or include an amount to convert. Full currency names work too. Click a suggestion to confirm ambiguous wording."
        case .interest:
            return "Write simple interest in Turkish or English, or try a natural phrase. Bobby asks you to review assumptions and fill in a missing principal before calculating."
        case .scratches:
            return "Start a separate scratch for each question, plan, or quick calculation. Everything you write stays together on your Mac."
        case .shortcuts:
            return "Bring up Bobby when you need a number, then return to what you were doing. Keep this quick reference handy."
        }
    }

    var example: String {
        switch self {
        case .math:
            return "2.5k + 750\n11.5m * 2%\n200k * .75"
        case .variables:
            return "rent = 25k TL\nmonths = 12\nrent * months"
        case .currency:
            return "USD TL\nTL euro\n3 USD to lira"
        case .interest:
            return "interest = 500k TL %40 yıllık 32 gün\ninterest * .75\n3 years interest at 42%"
        case .scratches, .shortcuts:
            return ""
        }
    }

    var tip: String {
        switch self {
        case .math:
            return "k means thousand, m means million, and 2% means 0.02. Use English numbers such as 1,234.56. No trailing = needed."
        case .variables:
            return "Variables belong to this scratch and apply from their definition downward. Click any answer to copy it."
        case .currency:
            return "TL and TRY are interchangeable. The rate source and date appear beside each answer. Hover for provider details. Reference rates can differ from your bank's rate."
        case .interest:
            return "Interest is principal × annual rate × days ÷ year basis. Suggestions need confirmation. Multiply by .75 for your own adjustment. Practice settings only affect this demo."
        case .scratches:
            return "Your existing scratches stay untouched throughout this tour. You can reopen the tutorial whenever you want."
        case .shortcuts:
            return "Ready to try your own numbers? Start with 11.5m * 2%, or write a note and let the next calculation follow."
        }
    }
}
