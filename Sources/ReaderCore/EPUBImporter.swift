import Foundation

public enum EPUBError: LocalizedError {
    case invalid(String)
    public var errorDescription: String? {
        switch self { case .invalid(let message): return message }
    }
}

public enum EPUBImporter {
    public static func load(_ url: URL) throws -> Book {
        let archive = try Archive(url)
        let container = try XMLDocumentReader(data: archive.read("META-INF/container.xml"))
        guard let packagePath = container.rootfile else { throw EPUBError.invalid("The EPUB has no package document.") }
        let package = try XMLDocumentReader(data: archive.read(packagePath))
        if archive.entries.contains("META-INF/encryption.xml") {
            let encryption = try archive.read("META-INF/encryption.xml")
            if String(decoding: encryption, as: UTF8.self).contains("EncryptedData") {
                throw EPUBError.invalid("This EPUB contains encrypted resources. This version supports unencrypted EPUBs.")
            }
        }
        var chapters: [Chapter] = []
        var totalLength = 0
        for id in package.spine {
            guard let item = package.manifest[id] else { throw EPUBError.invalid("An EPUB chapter is missing from its manifest.") }
            guard item.type == "application/xhtml+xml" || item.type == "text/html" else { continue }
            let path = try resolve(item.href, relativeTo: packagePath)
            let document = try XMLDocumentReader(data: archive.read(path))
            let text = document.body.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            totalLength += text.utf16.count
            guard totalLength <= 5_000_000 else { throw EPUBError.invalid("This book is too large for this version (5 million characters maximum).") }
            let title = document.heading.trimmingCharacters(in: .whitespacesAndNewlines)
            chapters.append(Chapter(id: path, title: title.isEmpty ? "Chapter \(chapters.count + 1)" : title, text: text))
        }
        guard !chapters.isEmpty else { throw EPUBError.invalid("No readable chapters were found in this EPUB.") }
        return Book(title: package.title.isEmpty ? url.deletingPathExtension().lastPathComponent : package.title,
                    author: package.author.isEmpty ? "Unknown author" : package.author, chapters: chapters)
    }

    public static func resolve(_ href: String, relativeTo package: String) throws -> String {
        let withoutFragment = String(href.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)[0])
        guard let decoded = withoutFragment.removingPercentEncoding, !decoded.hasPrefix("/"),
              !decoded.contains(":"), !decoded.contains("\\") else { throw EPUBError.invalid("An EPUB resource has an invalid path.") }
        var components = package.split(separator: "/").dropLast().map(String.init)
        for part in decoded.split(separator: "/").map(String.init) {
            if part == "." { continue }
            if part == ".." {
                guard !components.isEmpty else { throw EPUBError.invalid("An EPUB resource escapes the book directory.") }
                components.removeLast()
            } else { components.append(part) }
        }
        return components.joined(separator: "/")
    }
}

private struct Archive {
    let url: URL
    let entries: Set<String>

    init(_ url: URL) throws {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        guard size <= 100_000_000 else { throw EPUBError.invalid("Please choose an EPUB smaller than 100 MB.") }
        self.url = url
        let listing = try Self.run(["-Z1", url.path], limit: 2_000_000)
        entries = Set(String(decoding: listing, as: UTF8.self).split(separator: "\n").map(String.init))
        guard entries.count <= 20_000 else { throw EPUBError.invalid("The EPUB contains too many resources.") }
        let mime = try read("mimetype")
        guard String(decoding: mime, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines) == "application/epub+zip" else {
            throw EPUBError.invalid("This file is not an EPUB archive.")
        }
    }

    func read(_ path: String) throws -> Data {
        guard entries.contains(path), !path.hasPrefix("/"),
              !path.split(separator: "/").contains(".."),
              !path.contains(where: { "*?[]\\".contains($0) }) else {
            throw EPUBError.invalid("A required EPUB resource is missing or has an unsupported path: \(path)")
        }
        // Read individual entries to stdout; never extract archive paths onto the filesystem.
        return try Self.run(["-p", url.path, path], limit: 16_000_000)
    }

    static func run(_ arguments: [String], limit: Int) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        try process.run()
        var result = Data()
        while let chunk = try pipe.fileHandleForReading.read(upToCount: 65_536), !chunk.isEmpty {
            result.append(chunk)
            if result.count > limit {
                process.terminate()
                try? pipe.fileHandleForReading.close()
                process.waitUntilExit()
                throw EPUBError.invalid("An EPUB resource exceeds the safe reading limit.")
            }
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw EPUBError.invalid("The EPUB archive could not be read.") }
        return result
    }
}

private final class XMLDocumentReader: NSObject, XMLParserDelegate {
    struct Item { let href: String; let type: String }
    var rootfile: String?
    var manifest: [String: Item] = [:]
    var spine: [String] = []
    var title = ""
    var author = ""
    var body = ""
    var heading = ""
    private var stack: [String] = []
    private var hiddenDepth = 0
    private var headingDepth: Int?
    private var didFindHeading = false
    private var parsedCharacters = 0
    private let blocks: Set<String> = ["p", "div", "section", "article", "h1", "h2", "h3", "h4", "li", "blockquote", "tr", "br"]

    init(data: Data) throws {
        super.init()
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.shouldResolveExternalEntities = false
        parser.delegate = self
        guard parser.parse() else { throw EPUBError.invalid("An EPUB document is malformed: \(parser.parserError?.localizedDescription ?? "invalid XML")") }
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes attrs: [String: String]) {
        stack.append(name)
        if name == "rootfile", rootfile == nil { rootfile = attrs["full-path"] }
        if name == "item", let id = attrs["id"], let href = attrs["href"] {
            manifest[id] = Item(href: href, type: attrs["media-type"] ?? "")
        }
        if name == "itemref", attrs["linear"] != "no", let id = attrs["idref"] { spine.append(id) }
        if hiddenDepth > 0 { hiddenDepth += 1; return }
        if ["script", "style", "nav"].contains(name) || attrs["hidden"] != nil || attrs["aria-hidden"] == "true" {
            hiddenDepth = 1; return
        }
        if stack.contains("body") {
            if blocks.contains(name) { paragraphBreak() }
            if ["h1", "h2"].contains(name), !didFindHeading { headingDepth = stack.count; didFindHeading = true }
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        parsedCharacters += string.utf16.count
        guard parsedCharacters <= 5_000_000 else { parser.abortParsing(); return }
        guard hiddenDepth == 0 else { return }
        if stack.contains("metadata") {
            if stack.last == "title" { title += string }
            if stack.last == "creator" { author += string }
        }
        if stack.contains("body") {
            // Collapse XHTML whitespace once. Speech and display use this exact same text.
            for character in string {
                if character.isWhitespace {
                    if let last = body.last, !last.isWhitespace { body.append(" ") }
                } else { body.append(character) }
            }
            if headingDepth != nil { heading += string }
        }
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        if hiddenDepth > 0 { hiddenDepth -= 1 }
        else if stack.contains("body"), blocks.contains(name) { paragraphBreak() }
        if headingDepth == stack.count { headingDepth = nil }
        _ = stack.popLast()
    }

    private func paragraphBreak() {
        while body.last == " " { body.removeLast() }
        if !body.isEmpty, !body.hasSuffix("\n\n") { body += "\n\n" }
    }
}
