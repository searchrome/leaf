import SwiftUI
import AppKit
import ReaderCore

@MainActor
final class LeafAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        if let url = Bundle.main.url(forResource: "Leaf", withExtension: "icns"),
           let icon = NSImage(contentsOf: url) {
            NSApplication.shared.applicationIconImage = icon
            NSApplication.shared.dockTile.display()
        }
    }
}

@main
struct LeafApp: App {
    @NSApplicationDelegateAdaptor(LeafAppDelegate.self) private var appDelegate
    @StateObject private var reader = ReaderModel()
    var body: some Scene {
        WindowGroup("Leaf") {
            ReaderView(reader: reader)
                .frame(minWidth: 850, minHeight: 600)
                .onOpenURL { reader.load($0) }
        }
        .defaultSize(width: 1140, height: 850)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Open EPUB…", action: reader.openBook).keyboardShortcut("o")
                Button("Library") { reader.showLibrary = true }.keyboardShortcut("l")
            }
            CommandMenu("Reading") {
                Button(reader.isReading ? "Pause" : "Read aloud", action: reader.toggleReading).keyboardShortcut(" ", modifiers: []).disabled(reader.passageChat != nil)
                Button(reader.canOpenListeningView ? "Next sentence" : "Next page") { reader.navigateReading(1) }
                    .keyboardShortcut(.rightArrow, modifiers: [])
                    .disabled(reader.showSettings || reader.showLibrary || reader.isImporting || reader.lookupResult != nil || reader.passageChat != nil)
                Button(reader.canOpenListeningView ? "Previous sentence" : "Previous page") { reader.navigateReading(-1) }
                    .keyboardShortcut(.leftArrow, modifiers: [])
                    .disabled(reader.showSettings || reader.showLibrary || reader.isImporting || reader.lookupResult != nil || reader.passageChat != nil)
                Button(reader.isListeningView ? "Exit listening view" : "Open listening view") {
                    reader.toggleListeningView()
                }
                .keyboardShortcut(KeyEquivalent("\u{F708}"), modifiers: [])
                .disabled(!reader.isListeningView && !reader.canOpenListeningView)
                Divider()
                Button("Bookmark Selected Text", action: reader.bookmarkSelectedText).disabled(!reader.hasTextSelection)
                Button("Chat About Selected Text", action: reader.chatAboutSelectedText).disabled(!reader.hasTextSelection || reader.passageChat != nil)
                Button("Look Up Selected Text", action: reader.lookUpSelectedText).disabled(!reader.hasTextSelection)
            }
        }
    }
}
