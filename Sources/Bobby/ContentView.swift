import AppKit
import SwiftUI

struct ContentView: View {
    @ObservedObject var model: AppModel
    let onHide: () -> Void
    let onFocusScratch: () -> Void
    @State private var showSidebar = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if let error = model.errorMessage {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.circle")
                    Text(error).font(.caption)
                    Spacer()
                    Button("Dismiss") { model.dismissError() }
                }
                .padding(12).background(Color.orange.opacity(0.12))
            }
            HStack(spacing: 0) {
                if showSidebar {
                    sidebar
                    Divider()
                }
                ScratchEditor(text: Binding(get: { model.currentText }, set: model.updateText),
                              scratchID: model.collection.selectedID, results: model.results,
                              onCopy: model.copy, onSelection: { model.selectedLine = $0 }, onHide: onHide,
                              onNavigate: { model.navigate($0 == .next ? 1 : -1) }, yearBasis: model.collection.yearBasis)
            }
            Divider()
            footer
        }
        .background(Color(nsColor: .textBackgroundColor))
        .tint(.teal)
        .sheet(isPresented: $model.showHelp, onDismiss: onFocusScratch) { TutorialView(model: model) }
        .sheet(isPresented: $model.showSettings, onDismiss: onFocusScratch) { settings }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Button { showSidebar.toggle() } label: { Image(systemName: "sidebar.left") }
                .help("Show scratches")
            VStack(alignment: .leading, spacing: 2) {
                Text("bobby").font(.system(size: 25, weight: .semibold, design: .rounded))
                Text("A little room for your numbers.").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button { model.showHelp = true } label: {
                Label("Take a tour", systemImage: "sparkles")
                    .font(.system(size: 12, weight: .medium))
            }
            .help("Try Bobby's features in a separate practice scratch")
            HStack(spacing: 5) {
                Button { model.navigate(-1) } label: { Image(systemName: "chevron.left") }
                    .help("Previous scratch, ⌘⌥←")
                Text("\((model.collection.scratches.firstIndex(where: { $0.id == model.collection.selectedID }) ?? 0) + 1) / \(model.collection.scratches.count)")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(minWidth: 40)
                Button { model.navigate(1) } label: { Image(systemName: "chevron.right") }
                    .help("Next scratch, ⌘⌥→")
            }
            Button { model.newScratch() } label: { Image(systemName: "plus") }.help("New scratch, ⌘N")
            Button { model.isPinned.toggle() } label: {
                Image(systemName: model.isPinned ? "pin.fill" : "pin")
                    .foregroundStyle(model.isPinned ? Color.teal : Color.secondary)
            }.help("Keep Bobby above other windows")
            Menu {
                Button("Copy scratch") { model.copy(model.currentText) }
                Button("Export text…") { model.exportScratch() }
                Button("Export Markdown…") { model.exportScratch(markdown: true) }
                Divider()
                Button("Refresh exchange rates") { model.refreshRates() }
                Button("Settings…") { model.showSettings = true }
                Button("Take a tour") { model.showHelp = true }
                Divider()
                Button("Delete scratch…", role: .destructive) { model.deleteCurrent() }
            } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).frame(width: 26)
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 22).padding(.vertical, 17)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var sidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 5) {
                Text("YOUR SCRATCHES").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                    .padding(.horizontal, 8).padding(.vertical, 10)
                ForEach(model.collection.scratches) { scratch in
                    Button { model.select(scratch.id) } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(model.title(for: scratch)).font(.system(size: 12, weight: .medium)).lineLimit(2)
                            Text(scratch.updatedAt, style: .date).font(.system(size: 10)).foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading).padding(10)
                        .background(scratch.id == model.collection.selectedID ? Color.teal.opacity(0.12) : .clear,
                                    in: RoundedRectangle(cornerRadius: 8))
                    }.buttonStyle(.plain)
                }
            }.padding(10)
        }
        .frame(width: 180).background(Color(nsColor: .windowBackgroundColor))
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Circle().fill(model.saveMessage == "Saved on this Mac" ? Color.teal : Color.orange).frame(width: 5, height: 5)
            Text(model.feedback ?? model.saveMessage).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text("Interest year").font(.caption).foregroundStyle(.secondary)
            Picker("Interest year", selection: Binding(get: { model.collection.yearBasis }, set: model.setYearBasis)) {
                ForEach([360, 365, 366], id: \.self) { Text("\($0) days").tag($0) }
            }.labelsHidden().frame(width: 92).controlSize(.small)
            Button { model.showHelp = true } label: { Image(systemName: "questionmark.circle") }
                .buttonStyle(.borderless).help("Tutorial and shortcuts")
        }
        .padding(.horizontal, 22).padding(.vertical, 11)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Settings").font(.title2.weight(.semibold))
            Picker("Show / hide Bobby", selection: $model.shortcutChoice) {
                ForEach(GlobalShortcut.choices, id: \.id) { choice in Text(choice.label).tag(choice.id) }
            }
            if let error = model.shortcutError { Text(error).font(.caption).foregroundStyle(.orange) }
            Text("English number format: 1,234.56. Finance terms can be English or Turkish. Interest is simple, with the year basis visible below your scratch.")
                .font(.callout).foregroundStyle(.secondary)
            HStack {
                Button("Open data folder") {
                    let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                        .appendingPathComponent("Bobby", isDirectory: true)
                    NSWorkspace.shared.open(directory)
                }
                Spacer()
                Button("Done") { model.showSettings = false }.keyboardShortcut(.defaultAction)
            }
        }.padding(28).frame(width: 440)
    }
}
