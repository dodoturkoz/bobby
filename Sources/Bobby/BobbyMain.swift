import AppKit
import Combine
import OSLog
import SwiftUI

@main
enum BobbyMain {
    @MainActor
    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.regular)
        application.run()
        withExtendedLifetime(delegate) {}
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuItemValidation {
    private var model: AppModel!
    private var window: NSWindow!
    private var statusItem: NSStatusItem!
    private let shortcut = GlobalShortcut()
    private var rateTimer: Timer?
    private var tutorialDismissalMonitor: Any?
    private var tutorialOutsideAppMonitor: Any?
    private var tutorialPresentedAt: TimeInterval?
    private var subscriptions = Set<AnyCancellable>()
    private let windowLog = Logger(subsystem: "com.dodoturkoz.bobby", category: "Window")

    func applicationDidFinishLaunching(_ notification: Notification) {
        model = AppModel()
        buildMenu()
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 640),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Bobby"
        window.minSize = NSSize(width: 820, height: 420)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(rootView: ContentView(model: model,
            onHide: { [weak self] in self?.hide() }, onFocusScratch: { [weak self] in self?.focusEditor(preferScratch: true) }))
        window.center()
        window.setFrameAutosaveName("BobbyScratchWindow")
        tutorialDismissalMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            guard let self, self.model.showHelp, let sheet = self.window.attachedSheet,
                  event.window === self.window else { return event }
            let location = self.window.convertPoint(toScreen: event.locationInWindow)
            guard !sheet.frame.contains(location) else { return event }
            self.windowLog.notice("Tutorial dismissed by a background click")
            self.closeNestedSheets(in: sheet)
            self.model.showHelp = false
            return nil
        }
        tutorialOutsideAppMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            guard let self, self.model.showHelp, self.window.isVisible,
                  self.window.attachedSheet != nil,
                  let presentedAt = self.tutorialPresentedAt, event.timestamp > presentedAt else { return }
            self.windowLog.notice("Tutorial dismissed by a click in another app")
            if let sheet = self.window.attachedSheet { self.closeNestedSheets(in: sheet) }
            self.model.showHelp = false
        }
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "b.circle", accessibilityDescription: "Bobby")
        statusItem.button?.toolTip = "Bobby, your finance scratchpad"
        let menu = NSMenu()
        add("Show / Hide Bobby", action: #selector(toggleWindow), to: menu)
        add("New scratch", action: #selector(newScratch), to: menu)
        menu.addItem(.separator())
        add("Settings…", action: #selector(settings), to: menu)
        add("Take a tour", action: #selector(help), to: menu)
        menu.addItem(.separator())
        add("Quit Bobby", action: #selector(quit), to: menu)
        statusItem.menu = menu
        model.$showHelp.sink { [weak self] showing in
            // Global monitors can deliver an activation click after the sheet
            // has opened. That older event must not dismiss the new tutorial.
            self?.tutorialPresentedAt = showing ? ProcessInfo.processInfo.systemUptime : nil
        }.store(in: &subscriptions)
        shortcut.onTrigger = { [weak self] in
            guard let self else { return }
            self.windowLog.notice("Global shortcut received")
            self.toggleWindow()
        }
        model.$shortcutChoice.removeDuplicates().sink { [weak self] choice in
            guard let self else { return }
            let success = self.shortcut.register(choice)
            DispatchQueue.main.async {
                self.model.shortcutError = success ? nil : "That shortcut is already in use. Choose another one."
            }
        }.store(in: &subscriptions)
        model.$isPinned.sink { [weak self] pinned in self?.window.level = pinned ? .floating : .normal }
            .store(in: &subscriptions)
        rateTimer = Timer.scheduledTimer(withTimeInterval: 900, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.model.refreshRates(force: false) }
        }
        show()
    }

    func applicationWillTerminate(_ notification: Notification) {
        rateTimer?.invalidate()
        if let tutorialDismissalMonitor { NSEvent.removeMonitor(tutorialDismissalMonitor) }
        if let tutorialOutsideAppMonitor { NSEvent.removeMonitor(tutorialOutsideAppMonitor) }
        model?.flushSave()
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func windowShouldClose(_ sender: NSWindow) -> Bool { hide(); return false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { show(); return true }
    func windowDidEndSheet(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in self?.focusEditor(preferScratch: true) }
    }

    private func show() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        focusEditor()
        windowLog.notice("Scratchpad shown")
        model.refreshRates(force: false)
    }

    private func focusEditor(preferScratch: Bool = false) {
        guard window.isVisible else { return }
        if preferScratch && window.attachedSheet != nil { return }
        let target = preferScratch ? window! : deepestSheet(of: window!)
        if let editor = findEditor(in: target.contentView) { target.makeFirstResponder(editor) }
        DispatchQueue.main.async { [weak self] in
            guard let self, !preferScratch || (!self.hasSheet) else { return }
            let target = preferScratch ? self.window! : self.deepestSheet(of: self.window!)
            guard target.isKeyWindow, let editor = self.findEditor(in: target.contentView) else { return }
            target.makeFirstResponder(editor)
        }
    }

    private func deepestSheet(of parent: NSWindow) -> NSWindow {
        var target = parent
        while let child = target.attachedSheet { target = child }
        return target
    }

    private func closeNestedSheets(in parent: NSWindow) {
        guard let child = parent.attachedSheet else { return }
        closeNestedSheets(in: child)
        parent.endSheet(child)
        child.orderOut(nil)
    }

    private func hide() {
        model.flushSave()
        window.orderOut(nil)
        windowLog.notice("Scratchpad hidden")
    }

    private func findEditor(in view: NSView?) -> NSTextView? {
        guard let view else { return nil }
        if let editor = view as? NSTextView { return editor }
        return view.subviews.compactMap { findEditor(in: $0) }.first
    }

    @objc private func toggleWindow() {
        if window.isVisible && deepestSheet(of: window!).isKeyWindow { hide() }
        else { show() }
    }
    private var hasSheet: Bool { model.showHelp || model.showSettings || window.attachedSheet != nil }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        guard let action = menuItem.action else { return true }
        if action == #selector(copyResult) { return !hasSheet || (model.showHelp && window.attachedSheet?.attachedSheet == nil) }
        let scratchActions: [Selector] = [#selector(newScratch), #selector(exportText), #selector(exportMarkdown),
                                          #selector(previousScratch), #selector(nextScratch), #selector(settings), #selector(help)]
        return !scratchActions.contains(action) || !hasSheet
    }

    @objc private func newScratch() { guard !hasSheet else { return }; model.newScratch(); show() }
    @objc private func copyResult() {
        if model.showHelp, window.attachedSheet?.attachedSheet == nil { NotificationCenter.default.post(name: Notification.Name("BobbyCopyTutorialAnswer"), object: nil) }
        else if !hasSheet { model.copyCurrentResult() }
    }
    @objc private func exportText() { guard !hasSheet else { return }; model.exportScratch() }
    @objc private func exportMarkdown() { guard !hasSheet else { return }; model.exportScratch(markdown: true) }
    @objc private func previousScratch() { guard !hasSheet else { return }; model.navigate(-1) }
    @objc private func nextScratch() { guard !hasSheet else { return }; model.navigate(1) }
    @objc private func settings() { guard !hasSheet else { return }; show(); model.showSettings = true }
    @objc private func help() { guard !hasSheet else { return }; show(); model.showHelp = true }
    @objc private func quit() { NSApp.terminate(nil) }

    private func buildMenu() {
        let main = NSMenu()
        let appMenu = NSMenu(title: "Bobby")
        add("About Bobby", action: #selector(about), to: appMenu)
        appMenu.addItem(.separator())
        add("Settings…", action: #selector(settings), key: ",", to: appMenu)
        appMenu.addItem(.separator())
        add("Hide Bobby", action: #selector(NSApplication.hide(_:)), key: "h", to: appMenu, target: NSApp)
        appMenu.addItem(.separator())
        add("Quit Bobby", action: #selector(quit), key: "q", to: appMenu)
        let file = NSMenu(title: "File")
        add("New scratch", action: #selector(newScratch), key: "n", to: file)
        add("Export text…", action: #selector(exportText), key: "s", to: file, modifiers: [.command, .shift])
        add("Export Markdown…", action: #selector(exportMarkdown), to: file)
        let edit = NSMenu(title: "Edit")
        add("Undo", action: Selector(("undo:")), key: "z", to: edit, target: nil)
        add("Redo", action: Selector(("redo:")), key: "z", to: edit, target: nil, modifiers: [.command, .shift])
        edit.addItem(.separator())
        add("Cut", action: #selector(NSText.cut(_:)), key: "x", to: edit, target: nil)
        add("Copy", action: #selector(NSText.copy(_:)), key: "c", to: edit, target: nil)
        add("Paste", action: #selector(NSText.paste(_:)), key: "v", to: edit, target: nil)
        add("Select All", action: #selector(NSText.selectAll(_:)), key: "a", to: edit, target: nil)
        edit.addItem(.separator())
        add("Copy line answer", action: #selector(copyResult), key: "c", to: edit, modifiers: [.command, .shift])
        let navigation = NSMenu(title: "Scratch")
        add("Previous scratch", action: #selector(previousScratch), key: String(UnicodeScalar(NSLeftArrowFunctionKey)!),
            to: navigation, modifiers: [.command, .option])
        add("Next scratch", action: #selector(nextScratch), key: String(UnicodeScalar(NSRightArrowFunctionKey)!),
            to: navigation, modifiers: [.command, .option])
        add("Take a tour", action: #selector(help), to: navigation)
        for submenu in [appMenu, file, edit, navigation] {
            let item = NSMenuItem()
            item.title = submenu.title
            item.submenu = submenu
            main.addItem(item)
        }
        NSApp.mainMenu = main
    }

    @objc private func about() {
        NSApp.orderFrontStandardAboutPanel(options: [.applicationName: "Bobby", .applicationVersion: "0.1.0",
                                                    .credits: NSAttributedString(string: "A little room for your numbers.")])
    }

    private func add(_ title: String, action: Selector, key: String = "", to menu: NSMenu,
                     target: AnyObject? = nil, modifiers: NSEvent.ModifierFlags = [.command]) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = target ?? (menu.title == "Edit" && ["undo:", "redo:", "cut:", "copy:", "paste:", "selectAll:"].contains(NSStringFromSelector(action)) ? nil : self)
        item.keyEquivalentModifierMask = modifiers
        menu.addItem(item)
    }
}
