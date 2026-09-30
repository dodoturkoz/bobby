import AppKit
import SwiftUI

struct ScratchEditor: NSViewRepresentable {
    @Binding var text: String
    let scratchID: UUID?
    let results: [DisplayResult]
    let onCopy: (String) -> Void
    let onSelection: (Int) -> Void
    let onHide: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        let editor = ResultTextView(frame: NSRect(x: 0, y: 0, width: 760, height: 450))
        editor.delegate = context.coordinator
        editor.isRichText = false
        editor.isAutomaticQuoteSubstitutionEnabled = false
        editor.isAutomaticDashSubstitutionEnabled = false
        editor.isAutomaticTextReplacementEnabled = false
        editor.isAutomaticSpellingCorrectionEnabled = false
        editor.isContinuousSpellCheckingEnabled = false
        editor.isGrammarCheckingEnabled = false
        editor.allowsUndo = true
        editor.isVerticallyResizable = true
        editor.isHorizontallyResizable = false
        editor.autoresizingMask = [.width]
        editor.minSize = NSSize(width: 0, height: 450)
        editor.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        editor.textContainerInset = NSSize(width: 28, height: 24)
        editor.textContainer?.widthTracksTextView = false
        editor.font = .monospacedSystemFont(ofSize: 16, weight: .regular)
        editor.textColor = .labelColor
        editor.insertionPointColor = .controlAccentColor
        editor.backgroundColor = .textBackgroundColor
        let paragraph = NSMutableParagraphStyle()
        paragraph.paragraphSpacing = 20
        paragraph.minimumLineHeight = 24
        editor.defaultParagraphStyle = paragraph
        editor.typingAttributes = [.font: editor.font!, .paragraphStyle: paragraph, .foregroundColor: NSColor.labelColor]
        editor.setAccessibilityLabel("Scratch text")
        editor.setAccessibilityIdentifier("scratch-editor")
        editor.string = text
        editor.onCopy = onCopy
        editor.onHide = onHide
        editor.displayResults = results
        scroll.documentView = editor
        context.coordinator.scratchID = scratchID
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        context.coordinator.parent = self
        guard let editor = scroll.documentView as? ResultTextView else { return }
        editor.onCopy = onCopy
        editor.onHide = onHide
        if context.coordinator.scratchID != scratchID {
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
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: ScratchEditor
        var scratchID: UUID?
        init(_ parent: ScratchEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let editor = notification.object as? ResultTextView else { return }
            parent.text = editor.string
            editor.layoutResults()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let editor = notification.object as? NSTextView else { return }
            let prefix = (editor.string as NSString).substring(to: min(editor.selectedRange().location, (editor.string as NSString).length))
            parent.onSelection(prefix.filter { $0 == "\n" }.count)
        }
    }
}

final class ResultTextView: NSTextView {
    var displayResults: [DisplayResult] = [] { didSet { needsLayout = true } }
    var onCopy: ((String) -> Void)?
    var onHide: (() -> Void)?
    private var resultButtons: [NSButton] = []
    private var resultValues: [ObjectIdentifier: String] = [:]
    private let resultWidth: CGFloat = 246

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
        if event.keyCode == 53 && !hasMarkedText() { onHide?() }
        else { super.keyDown(with: event) }
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
        let lines = string.components(separatedBy: "\n")
        var starts: [Int] = []
        var offset = 0
        for line in lines {
            starts.append(offset)
            offset += (line as NSString).length + 1
        }
        for result in displayResults {
            guard starts.indices.contains(result.lineIndex), starts[result.lineIndex] < (string as NSString).length else { continue }
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
            let title = NSMutableAttributedString(string: result.text, attributes: [
                .font: NSFont.monospacedDigitSystemFont(ofSize: 15, weight: .semibold),
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
            addSubview(button)
            resultButtons.append(button)
        }
        setAccessibilityChildren(resultButtons)
        needsDisplay = true
    }

    @objc private func copyResult(_ button: NSButton) {
        guard let value = resultValues[ObjectIdentifier(button)] else { return }
        onCopy?(value)
        window?.makeFirstResponder(self)
    }
}
