import SwiftUI
import AppKit
import ReaderCore

struct PageText: NSViewRepresentable {
    let text: String
    let fontSize: CGFloat
    let highlight: NSRange?
    let bookmarks: [NSRange]
    let selectedBookmark: NSRange?
    let selectedBookmarkID: UUID?
    let onSeek: (Int) -> Void
    let onSelection: (NSRange) -> Void
    let onBookmarkHit: (Int) -> Bool
    let onRemoveBookmark: () -> Void
    let onBookmark: () -> Void
    let onLookup: () -> Void

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: PageText
        var updatingView = false

        init(_ parent: PageText) { self.parent = parent }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard !updatingView else { return }
            guard let view = notification.object as? NSTextView else { return }
            parent.onSelection(view.selectedRange())
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class SeekTextView: NSTextView {
        var onSeek: ((Int) -> Void)?
        var onBookmarkHit: ((Int) -> Bool)?
        var onBookmark: (() -> Void)?
        var onLookup: (() -> Void)?
        var onRemoveBookmark: (() -> Void)?
        var removalRange: NSRange?
        private(set) lazy var removeButton: NSButton = {
            let button = NSButton(title: "×", target: self, action: #selector(removeSelectedBookmark))
            button.isBordered = false
            button.wantsLayer = true
            button.layer?.backgroundColor = NSColor.selectedTextBackgroundColor.cgColor
            button.layer?.cornerRadius = 6
            button.contentTintColor = .selectedTextColor
            button.font = .systemFont(ofSize: 18, weight: .semibold)
            button.toolTip = "Remove this bookmark"
            button.setAccessibilityLabel("Remove selected bookmark")
            addSubview(button)
            return button
        }()

        @objc private func removeSelectedBookmark() { onRemoveBookmark?() }

        func positionRemoveButton() {
            guard let range = removalRange, range.length > 0,
                  NSMaxRange(range) <= (string as NSString).length,
                  let layoutManager, let container = textContainer else {
                removeButton.isHidden = true
                return
            }
            layoutManager.ensureLayout(for: container)
            let glyph = layoutManager.glyphIndexForCharacter(at: NSMaxRange(range) - 1)
            let rect = layoutManager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: container)
            removeButton.frame = NSRect(
                x: min(max(0, rect.maxX + textContainerOrigin.x + 4), max(0, bounds.width - 26)),
                y: min(max(0, rect.midY + textContainerOrigin.y - 13), max(0, bounds.height - 26)),
                width: 26, height: 26)
            removeButton.isHidden = false
        }

        override func layout() {
            super.layout()
            positionRemoveButton()
        }
        var displayedBookmarkID: UUID?
        var bookmarkRanges: [NSRange] = []
        private var downPoint: NSPoint?

        override func mouseDown(with event: NSEvent) {
            let point = convert(event.locationInWindow, from: nil)
            if event.clickCount == 1, !event.modifierFlags.contains(.shift),
               let index = characterAtPoint(point),
               let range = bookmarkRanges.first(where: { NSLocationInRange(index, $0) }),
               onBookmarkHit?(index) == true {
                window?.makeFirstResponder(self)
                setSelectedRange(range)
                downPoint = nil
                return
            }
            downPoint = point
            super.mouseDown(with: event)
        }

        /// Hit the glyph itself, not the nearest insertion position in blank space.
        func characterAtPoint(_ point: NSPoint) -> Int? {
            guard let layoutManager, let container = textContainer, !string.isEmpty else { return nil }
            layoutManager.ensureLayout(for: container)
            let local = NSPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)
            let glyph = layoutManager.glyphIndex(for: local, in: container)
            guard glyph < layoutManager.numberOfGlyphs,
                  layoutManager.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: container).contains(local) else { return nil }
            return layoutManager.characterIndexForGlyph(at: glyph)
        }

        override func mouseUp(with event: NSEvent) {
            defer { downPoint = nil }
            let upPoint = convert(event.locationInWindow, from: nil)
            let dragged = downPoint.map { abs($0.x - upPoint.x) > 3 || abs($0.y - upPoint.y) > 3 } ?? true
            if !dragged {
                var fraction = CGFloat(0)
                if let layoutManager, let container = textContainer {
                    var index = layoutManager.characterIndex(for: upPoint, in: container, fractionOfDistanceBetweenInsertionPoints: &fraction)
                    let length = (string as NSString).length
                    if index != NSNotFound, index >= length { index = max(0, length - 1) }
                    if index != NSNotFound, index >= 0 {
                        if onBookmarkHit?(index) == true {
                            super.mouseUp(with: event)
                            return
                        }
                        onSeek?(index)
                    }
                }
            }
            super.mouseUp(with: event)
        }

        override func menu(for event: NSEvent) -> NSMenu? {
            let menu = super.menu(for: event) ?? NSMenu()
            guard selectedRange().length > 0 else { return menu }
            let bookmark = NSMenuItem(title: "Bookmark Selected Text", action: #selector(bookmarkSelection), keyEquivalent: "")
            bookmark.target = self
            let lookup = NSMenuItem(title: "Look Up Selected Text", action: #selector(lookUpSelection), keyEquivalent: "")
            lookup.target = self
            menu.insertItem(.separator(), at: 0)
            menu.insertItem(lookup, at: 0)
            menu.insertItem(bookmark, at: 0)
            return menu
        }

        @objc private func bookmarkSelection() { onBookmark?() }
        @objc private func lookUpSelection() { onLookup?() }
    }

    func makeNSView(context: Context) -> NSTextView {
        let view = SeekTextView()
        view.isEditable = false
        view.isSelectable = true
        view.drawsBackground = false
        view.textContainerInset = .zero
        view.textContainer?.lineFragmentPadding = 0
        view.isVerticallyResizable = false
        view.isHorizontallyResizable = false
        view.textContainer?.widthTracksTextView = true
        view.textContainer?.heightTracksTextView = true
        view.setAccessibilityLabel("Book page")
        view.onSeek = onSeek
        view.onBookmarkHit = onBookmarkHit
        view.bookmarkRanges = bookmarks
        view.onBookmark = onBookmark
        view.onLookup = onLookup
        view.delegate = context.coordinator
        return view
    }

    func updateNSView(_ view: NSTextView, context: Context) {
        context.coordinator.updatingView = true
        defer { context.coordinator.updatingView = false }
        context.coordinator.parent = self
        if let seekView = view as? SeekTextView {
            seekView.onSeek = onSeek
            seekView.onBookmarkHit = onBookmarkHit
            seekView.bookmarkRanges = bookmarks
            seekView.onBookmark = onBookmark
            seekView.onLookup = onLookup
            seekView.onRemoveBookmark = onRemoveBookmark
            seekView.removalRange = selectedBookmark
        }
        if view.string != text || view.font?.pointSize != fontSize {
            view.textStorage?.setAttributedString(Pagination.attributed(text, fontSize: fontSize))
        }
        if let seekView = view as? SeekTextView, seekView.displayedBookmarkID != selectedBookmarkID {
            seekView.displayedBookmarkID = selectedBookmarkID
            if let selectedBookmark { view.setSelectedRange(selectedBookmark) }
        }
        let entire = NSRange(location: 0, length: (text as NSString).length)
        view.layoutManager?.removeTemporaryAttribute(.backgroundColor, forCharacterRange: entire)
        for bookmark in bookmarks where bookmark.location >= 0 && NSMaxRange(bookmark) <= entire.length {
            view.layoutManager?.addTemporaryAttribute(.backgroundColor, value: NSColor(calibratedRed: 0.94, green: 0.88, blue: 0.55, alpha: 0.55), forCharacterRange: bookmark)
        }
        if let highlight, NSMaxRange(highlight) <= entire.length {
            view.layoutManager?.addTemporaryAttribute(.backgroundColor, value: NSColor(calibratedRed: 0.77, green: 0.85, blue: 0.62, alpha: 0.9), forCharacterRange: highlight)
        }
        (view as? SeekTextView)?.positionRemoveButton()
    }
}
