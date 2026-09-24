import XCTest
@testable import ReaderCore

final class EPUBImporterTests: XCTestCase {
    func testResolvesRelativeAndEncodedPathsButRejectsEscapes() throws {
        XCTAssertEqual(try EPUBImporter.resolve("../Text/One%20Day.xhtml#title", relativeTo: "OPS/package/book.opf"), "OPS/Text/One Day.xhtml")
        for path in ["../../escape", "/absolute.xhtml", "https://example.com/book", "%2e%2e/%2e%2e/secret", "..\\secret"] {
            XCTAssertThrowsError(try EPUBImporter.resolve(path, relativeTo: "OPS/book.opf"))
        }
    }

    func testReadsSpineOrderEntitiesUnicodeAndSkipsHiddenText() throws {
        let url = try fixture()
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        let book = try EPUBImporter.load(url)
        XCTAssertEqual(book.title, "Test & Book")
        XCTAssertEqual(book.author, "Reader")
        XCTAssertEqual(book.chapters.map(\.title), ["First", "Second"])
        XCTAssertTrue(book.chapters[0].text.contains("Café 👩🏽‍🚀 & tea."))
        XCTAssertFalse(book.chapters[0].text.contains("SECRET"))
        XCTAssertFalse(book.chapters[0].text.contains("NAVIGATION"))
    }

    func testRejectsMalformedChapter() throws {
        let url = try fixture(malformed: true)
        defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
        XCTAssertThrowsError(try EPUBImporter.load(url))
    }

    private func fixture(malformed: Bool = false) throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("leaf-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("META-INF"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("OPS"), withIntermediateDirectories: true)
        let files = [
            "mimetype": "application/epub+zip",
            "META-INF/container.xml": "<container><rootfiles><rootfile full-path=\"OPS/book.opf\"/></rootfiles></container>",
            "OPS/book.opf": "<package xmlns:dc=\"http://purl.org/dc/elements/1.1/\"><metadata><dc:title>Test &amp; Book</dc:title><dc:creator>Reader</dc:creator></metadata><manifest><item id=\"b\" href=\"b.xhtml\" media-type=\"application/xhtml+xml\"/><item id=\"a\" href=\"a.xhtml\" media-type=\"application/xhtml+xml\"/></manifest><spine><itemref idref=\"a\"/><itemref idref=\"b\"/></spine></package>",
            "OPS/a.xhtml": malformed ? "<html><body>broken" : "<html><head><title>Ignore</title></head><body><nav>NAVIGATION</nav><h1>First</h1><p>Café 👩🏽‍🚀 &amp; tea.</p><p hidden=\"hidden\">SECRET <b>SECRET</b></p><script>SECRET</script></body></html>",
            "OPS/b.xhtml": "<html><body><h1>Second</h1><p>The end.</p></body></html>"
        ]
        for (path, text) in files { try Data(text.utf8).write(to: root.appendingPathComponent(path)) }
        let archive = root.appendingPathComponent("fixture.epub")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.currentDirectoryURL = root
        process.arguments = ["-q", "-r", archive.path, "mimetype", "META-INF", "OPS"]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        return archive
    }
}
