import AppKit
import BobbyCore
import SwiftUI

struct ScratchEditor: NSViewRepresentable {
    @Binding var text: String
    let scratchID: UUID?
    let results: [DisplayResult]
    let onCopy: (String) -> Void
    let onSelection: (Int) -> Void
    let onHide: () -> Void
    var onNavigate: ((ScratchNavigationDirection) -> UUID?)? = nil
    var selectedScratchID: (() -> UUID?)? = nil
    var yearBasis: Int = 365
    var previousPage: ScratchPagePreview? = nil
    var nextPage: ScratchPagePreview? = nil
    var onPreviewResults: ((String) -> [DisplayResult])? = nil

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    static func dismantleNSView(_ pager: ScratchPagerView, coordinator: Coordinator) {
        let scroll = pager.scrollView
        (scroll.documentView as? ResultTextView)?.closeInterestReview()
        pager.cancelTransition()
        pager.onNavigate = nil
    }

    func makeNSView(context: Context) -> ScratchPagerView {
        context.coordinator.isSynchronizing = true
        defer { context.coordinator.isSynchronizing = false }
        let pager = ScratchPagerView(frame: NSRect(x: 0, y: 0, width: 760, height: 450))
        pager.onNavigate = onNavigate
        pager.selectedScratchID = selectedScratchID
        pager.onPreviewResults = onPreviewResults
        context.coordinator.pager = pager
        let scroll = pager.scrollView
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        let editor = ResultTextView(frame: NSRect(x: 0, y: 0, width: 760, height: 450))
        editor.delegate = context.coordinator
        editor.configureScratchAppearance()
        editor.onPrepareInteraction = { [weak pager] in pager?.prepareForInteraction() ?? true }
        editor.setAccessibilityLabel("Scratch text")
        editor.setAccessibilityIdentifier("scratch-editor")
        editor.string = text
        editor.representedScratchID = scratchID
        editor.onCopy = onCopy
        editor.onHide = onHide
        editor.interestYearBasis = yearBasis
        editor.displayResults = results
        scroll.documentView = editor
        context.coordinator.scratchID = scratchID
        pager.updatePages(currentID: scratchID, text: text, previous: previousPage, next: nextPage)
        return pager
    }

    func updateNSView(_ pager: ScratchPagerView, context: Context) {
        let scroll = pager.scrollView
        context.coordinator.parent = self
        context.coordinator.isSynchronizing = true
        defer { context.coordinator.isSynchronizing = false }
        pager.onNavigate = onNavigate
        pager.selectedScratchID = selectedScratchID
        pager.onPreviewResults = onPreviewResults
        guard let editor = scroll.documentView as? ResultTextView else { return }
        editor.onCopy = onCopy
        editor.onHide = onHide
        editor.interestYearBasis = yearBasis
        editor.representedScratchID = scratchID
        if context.coordinator.scratchID != scratchID {
            editor.closeInterestReview()
            editor.string = text
            editor.undoManager?.removeAllActions()
            editor.setSelectedRange(NSRange(location: 0, length: 0))
            editor.scrollRangeToVisible(NSRange(location: 0, length: 0))
            context.coordinator.scratchID = scratchID
            DispatchQueue.main.async { editor.window?.makeFirstResponder(editor) }
        } else if editor.string != text {
            let selection = editor.selectedRange()
            editor.string = text
            editor.setSelectedRange(NSRange(location: min(selection.location, (text as NSString).length), length: 0))
        }
        editor.displayResults = results
        editor.layoutResults()
        pager.updatePages(currentID: scratchID, text: text, previous: previousPage, next: nextPage)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ScratchEditor
        var scratchID: UUID?
        var isSynchronizing = false
        weak var pager: ScratchPagerView?
        init(_ parent: ScratchEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard !isSynchronizing, pager?.isAwaitingEditor != true else { return }
            guard let editor = notification.object as? ResultTextView else { return }
            parent.text = editor.string
            editor.layoutResults()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard !isSynchronizing, pager?.isAwaitingEditor != true else { return }
            guard let editor = notification.object as? NSTextView else { return }
            let prefix = (editor.string as NSString).substring(to: min(editor.selectedRange().location, (editor.string as NSString).length))
            parent.onSelection(prefix.filter { $0 == "\n" }.count)
        }

        func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
            isSynchronizing || (pager?.prepareForInteraction() ?? true)
        }
    }
}

final class ResultTextView: NSTextView {
    var displayResults: [DisplayResult] = [] { didSet { needsLayout = true } }
    var onCopy: ((String) -> Void)?
    var onHide: (() -> Void)?
    var onPrepareInteraction: (() -> Bool)?
    private var resultButtons: [NSButton] = []
    private var resultValues: [ObjectIdentifier: String] = [:]
    private var resultSuggestions: [ObjectIdentifier: (Int, String, CalculationSuggestion)] = [:]
    private var interestReviewPanel: NSPanel?
    var representedScratchID: UUID?
    private let resultWidth: CGFloat = 246

    func configureScratchAppearance() {
        isRichText = false
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isAutomaticSpellingCorrectionEnabled = false
        isContinuousSpellCheckingEnabled = false
        isGrammarCheckingEnabled = false
        allowsUndo = true
        isVerticallyResizable = true
        isHorizontallyResizable = false
        autoresizingMask = [.width]
        minSize = NSSize(width: 0, height: 450)
        maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textContainerInset = NSSize(width: 28, height: 24)
        textContainer?.widthTracksTextView = false
        font = .monospacedSystemFont(ofSize: 16, weight: .regular)
        textColor = .labelColor
        insertionPointColor = .controlAccentColor
        backgroundColor = .textBackgroundColor
        let paragraph = NSMutableParagraphStyle()
        paragraph.paragraphSpacing = 20
        paragraph.minimumLineHeight = 24
        defaultParagraphStyle = paragraph
        typingAttributes = [.font: font!, .paragraphStyle: paragraph, .foregroundColor: NSColor.labelColor]
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        textContainer?.containerSize = NSSize(width: max(180, newSize.width - resultWidth - textContainerInset.width * 2),
                                             height: .greatestFiniteMagnitude)
        needsLayout = true
    }

    override func layout() {
        super.layout()
        layoutResults()
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        NSColor.separatorColor.withAlphaComponent(0.45).setStroke()
        let rule = NSBezierPath()
        let x = bounds.width - resultWidth - 8
        rule.move(to: NSPoint(x: x, y: max(0, dirtyRect.minY)))
        rule.line(to: NSPoint(x: x, y: dirtyRect.maxY))
        rule.lineWidth = 1
        rule.stroke()
    }

    override func cancelOperation(_ sender: Any?) { onHide?() }

    override func keyDown(with event: NSEvent) {
        guard onPrepareInteraction?() != false else { return }
        if event.keyCode == 53 && !hasMarkedText() { onHide?() }
        else { super.keyDown(with: event) }
    }

    override func mouseDown(with event: NSEvent) {
        guard onPrepareInteraction?() != false else { return }
        super.mouseDown(with: event)
    }

    func layoutResults() {
        guard let layoutManager, let textContainer else { return }
        let desiredWidth = max(180, bounds.width - resultWidth - textContainerInset.width * 2)
        if abs(textContainer.containerSize.width - desiredWidth) > 0.5 {
            textContainer.containerSize = NSSize(width: desiredWidth, height: .greatestFiniteMagnitude)
        }
        layoutManager.ensureLayout(for: textContainer)
        resultButtons.forEach { $0.removeFromSuperview() }
        resultButtons = []
        resultValues = [:]
        resultSuggestions = [:]
        let lines = string.components(separatedBy: "\n")
        var starts: [Int] = []
        var offset = 0
        for line in lines {
            starts.append(offset)
            offset += (line as NSString).length + 1
        }
        for result in displayResults {
            guard starts.indices.contains(result.lineIndex), starts[result.lineIndex] < (string as NSString).length else { continue }
            if result.suggestion != nil, result.sourceLine != lines[result.lineIndex] { continue }
            let character = starts[result.lineIndex]
            let glyph = layoutManager.glyphIndexForCharacter(at: character)
            let rect = layoutManager.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            let button = NSButton(frame: NSRect(x: bounds.width - resultWidth + 10,
                                               y: textContainerOrigin.y + rect.minY - 3,
                                               width: resultWidth - 26, height: 42))
            button.isBordered = false
            button.setButtonType(.momentaryChange)
            button.alignment = .left
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineBreakMode = .byTruncatingTail
            var displayedText = result.text
            var valueFont = result.suggestion == nil ? NSFont.monospacedDigitSystemFont(ofSize: result.usesCompactValue ? 13 : 15, weight: .semibold) : NSFont.systemFont(ofSize: 12, weight: .semibold)
            if result.usesCompactValue,
               (result.text as NSString).size(withAttributes: [.font: valueFont]).width > button.cell!.titleRect(forBounds: button.bounds).width,
               let separator = result.text.range(of: " · Dealer sell ") {
                displayedText.replaceSubrange(separator, with: " TL\nDealer sell ")
                valueFont = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
                button.frame.size.height = 44
            }
            let title = NSMutableAttributedString(string: displayedText, attributes: [
                .font: valueFont,
                .foregroundColor: result.isError ? NSColor.systemOrange : NSColor.systemTeal,
                .paragraphStyle: paragraph
            ])
            if !result.detail.isEmpty {
                title.append(NSAttributedString(string: "\n" + result.detail, attributes: [
                    .font: NSFont.systemFont(ofSize: 10.5), .foregroundColor: NSColor.secondaryLabelColor,
                    .paragraphStyle: paragraph
                ]))
            }
            button.attributedTitle = title
            button.toolTip = result.tooltip + (result.copyText == nil ? "" : "\nClick to copy")
            button.setAccessibilityLabel(result.text)
            button.setAccessibilityHelp(result.tooltip)
            button.setAccessibilityIdentifier("result-line-\(result.lineIndex)")
            button.target = self
            button.action = #selector(copyResult(_:))
            if let value = result.copyText { resultValues[ObjectIdentifier(button)] = value }
            if let suggestion = result.suggestion, let sourceLine = result.sourceLine {
                resultSuggestions[ObjectIdentifier(button)] = (result.lineIndex, sourceLine, suggestion)
                button.toolTip = result.tooltip + "\nClick to review this interpretation"
                button.setAccessibilityHelp(button.toolTip)
                button.setAccessibilityIdentifier("suggestion-line-\(result.lineIndex)")
            }
            addSubview(button)
            resultButtons.append(button)
        }
        setAccessibilityChildren(resultButtons)
        needsDisplay = true
    }

    @objc private func copyResult(_ button: NSButton) {
        guard onPrepareInteraction?() != false else { return }
        if let (lineIndex, expectedLine, suggestion) = resultSuggestions[ObjectIdentifier(button)] {
            let lines = string.components(separatedBy: "\n")
            guard lines.indices.contains(lineIndex), lines[lineIndex] == expectedLine else { return }
            switch suggestion {
            case .currency(let expression, _):
                applySuggestion(expression, lineIndex: lineIndex, expectedLine: expectedLine)
            case .interest(let proposal):
                presentInterestReview(proposal.interest, lineIndex: lineIndex, expectedLine: expectedLine)
            }
            return
        }
        guard let value = resultValues[ObjectIdentifier(button)] else { return }
        onCopy?(value)
        window?.makeFirstResponder(self)
    }

    private func applySuggestion(_ expression: String, lineIndex: Int, expectedLine: String) {
        guard let edit = SuggestionLineEdit.make(in: string, lineIndex: lineIndex,
                                                 expectedLine: expectedLine, expression: expression) else { return }
        // Use NSTextView's normal edit path, retaining native undo and notifying
        // the binding instead of replacing the whole saved scratch externally.
        insertText(edit.replacement, replacementRange: edit.range)
        undoManager?.setActionName("Accept interpretation")
        window?.makeFirstResponder(self)
    }

    private func presentInterestReview(_ draft: InterestDraft, lineIndex: Int, expectedLine: String) {
        guard interestReviewPanel == nil, let parentWindow = window else { return }
        let originalDocument = string
        let originalScratchID = representedScratchID
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 510, height: 460),
                            styleMask: [.titled], backing: .buffered, defer: false)
        panel.title = "Review simple interest"
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView: InterestReviewView(
            draft: draft, originalLine: expectedLine, initialYearBasis: interestYearBasis,
            onCancel: { [weak self] in self?.closeInterestReview() },
            onAccept: { [weak self] expression in
                self?.closeInterestReview()
                guard self?.string == originalDocument, self?.representedScratchID == originalScratchID else { return }
                self?.applySuggestion(expression, lineIndex: lineIndex, expectedLine: expectedLine)
            }))
        interestReviewPanel = panel
        parentWindow.beginSheet(panel) { [weak self] _ in
            if self?.interestReviewPanel === panel { self?.interestReviewPanel = nil }
            if parentWindow.isVisible, parentWindow.attachedSheet == nil { parentWindow.makeFirstResponder(self) }
        }
    }

    var interestYearBasis = 365

    func closeInterestReview() {
        guard let panel = interestReviewPanel else { return }
        panel.sheetParent?.endSheet(panel)
        panel.orderOut(nil)
        interestReviewPanel = nil
    }
}
