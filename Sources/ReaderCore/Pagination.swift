import AppKit

public enum Pagination {
    public static func attributed(_ text: String, fontSize: CGFloat) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = fontSize * 0.38
        paragraph.paragraphSpacing = fontSize * 0.7
        paragraph.lineBreakMode = .byWordWrapping
        return NSAttributedString(string: text, attributes: [
            .font: NSFont(name: "Georgia", size: fontSize) ?? NSFont.systemFont(ofSize: fontSize),
            .foregroundColor: NSColor(calibratedRed: 0.20, green: 0.23, blue: 0.21, alpha: 1),
            .paragraphStyle: paragraph
        ])
    }

    public static func pages(for text: String, fontSize: CGFloat, size: CGSize) -> [NSRange] {
        guard !text.isEmpty else { return [NSRange(location: 0, length: 0)] }
        let storage = NSTextStorage(attributedString: attributed(text, fontSize: fontSize))
        let layout = NSLayoutManager()
        storage.addLayoutManager(layout)
        var pages: [NSRange] = []
        var consumed = 0
        while consumed < storage.length {
            let container = NSTextContainer(size: CGSize(width: max(200, size.width), height: max(150, size.height)))
            container.lineFragmentPadding = 0
            layout.addTextContainer(container)
            layout.ensureLayout(for: container)
            let glyphs = layout.glyphRange(for: container)
            let characters = layout.characterRange(forGlyphRange: glyphs, actualGlyphRange: nil)
            let end = NSMaxRange(characters)
            guard end > consumed else { break }
            pages.append(NSRange(location: consumed, length: end - consumed))
            consumed = end
        }
        // Defensive fallback avoids dropping content even if TextKit cannot lay out a glyph.
        if consumed < storage.length { pages.append(NSRange(location: consumed, length: storage.length - consumed)) }
        return pages
    }
}
