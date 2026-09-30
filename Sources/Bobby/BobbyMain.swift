import AppKit
import Combine
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
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private var model: AppModel!
    private var window: NSWindow!
    private var statusItem: NSStatusItem!
    private let shortcut = GlobalShortcut()
    private var subscriptions = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        model = AppModel()
        buildMenu()
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1000, height: 640),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.title = "Bobby"
        window.minSize = NSSize(width: 820, height: 420)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(rootView: ContentView(model: model, onHide: { [weak self] in self?.hide() }))
        window.center()
        window.setFrameAutosaveName("BobbyScratchWindow")
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "b.circle", accessibilityDescription: "Bobby")
        statusItem.button?.toolTip = "Bobby, your finance scratchpad"
        let menu = NSMenu()
        add("Show / Hide Bobby", action: #selector(toggleWindow), to: menu)
        add("New scratch", action: #selector(newScratch), to: menu)
        menu.addItem(.separator())
        add("Settings…", action: #selector(settings), to: menu)
        add("Examples & shortcuts", action: #selector(help), to: menu)
        menu.addItem(.separator())
        add("Quit Bobby", action: #selector(quit), to: menu)
        statusItem.menu = menu
        shortcut.onTrigger = { [weak self] in self?.toggleWindow() }
        model.$shortcutChoice.removeDuplicates().sink { [weak self] choice in
            guard let self else { return }
            let success = self.shortcut.register(choice)
            DispatchQueue.main.async {
                self.model.shortcutError = success ? nil : "That shortcut is already in use. Choose another one."
            }
        }.store(in: &subscriptions)
        model.$isPinned.sink { [weak self] pinned in self?.window.level = pinned ? .floating : .normal }
            .store(in: &subscriptions)
        show()
    }

    func applicationWillTerminate(_ notification: Notification) { model?.flushSave() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func windowShouldClose(_ sender: NSWindow) -> Bool { hide(); return false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { show(); return true }

    private func show() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        if let editor = findEditor(in: window.contentView) { window.makeFirstResponder(editor) }
        model.refreshRates(force: false)
    }

    private func hide() { model.flushSave(); window.orderOut(nil) }

    private func findEditor(in view: NSView?) -> NSTextView? {
        guard let view else { return nil }
        if let editor = view as? NSTextView { return editor }
        return view.subviews.compactMap { findEditor(in: $0) }.first
    }

    @objc private func toggleWindow() {
        if window.isVisible && window.isKeyWindow { hide() } else { show() }
    }
    @objc private func newScratch() { model.newScratch(); show() }
    @objc private func copyResult() { model.copyCurrentResult() }
    @objc private func exportText() { model.exportScratch() }
    @objc private func exportMarkdown() { model.exportScratch(markdown: true) }
    @objc private func previousScratch() { model.navigate(-1) }
    @objc private func nextScratch() { model.navigate(1) }
    @objc private func settings() { show(); model.showSettings = true }
    @objc private func help() { show(); model.showHelp = true }
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
        add("Examples & shortcuts", action: #selector(help), to: navigation)
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
