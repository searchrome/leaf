import XCTest
@testable import Leaf

final class BookLibraryTests: XCTestCase {
    @MainActor
    func testSwitchingBooksPersistsSeparatePositionsAndRestoresAfterRelaunch() async throws {
        let suite = "leaf-library-test-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        defer { try? FileManager.default.removeItem(at: root) }
        let first = try fixture(root: root.appendingPathComponent("first"), title: "First book")
        let second = try fixture(root: root.appendingPathComponent("second"), title: "Second book")
        let reader = ReaderModel(restorePosition: false, defaults: defaults)
        reader.load(first)
        try await waitForImport(reader)
        reader.selectChapter(1)
        reader.turnPage(1)
        let savedPage = reader.pageIndex
        XCTAssertGreaterThan(savedPage, 0)
        reader.load(second)
        try await waitForImport(reader)
        XCTAssertEqual(reader.library.map(\.title), ["Second book", "First book"])
        reader.showLibrary = true
        reader.openLibraryBook(try XCTUnwrap(reader.library.last))
        try await waitForImport(reader)
        XCTAssertFalse(reader.showLibrary)
        XCTAssertEqual(reader.book.title, "First book")
        XCTAssertEqual(reader.chapterIndex, 1)
        XCTAssertEqual(reader.pageIndex, savedPage)
        XCTAssertEqual(reader.library.count, 2)
        let relaunched = ReaderModel(defaults: defaults)
        try await waitForImport(relaunched)
        XCTAssertEqual(relaunched.book.title, "First book")
        XCTAssertEqual(relaunched.chapterIndex, 1)
        XCTAssertEqual(relaunched.pageIndex, savedPage)
        XCTAssertEqual(relaunched.library.count, 2)

        let missing = try XCTUnwrap(relaunched.library.last)
        try FileManager.default.removeItem(at: second)
        relaunched.openLibraryBook(missing)
        XCTAssertNotNil(relaunched.error)
        XCTAssertEqual(relaunched.book.title, "First book")
        relaunched.removeLibraryBook(missing)
        XCTAssertEqual(BookLibraryStore.load(defaults: defaults).count, 1)
    }

    @MainActor
    func testFailedImportDoesNotEnterLibraryOrConsumeNextBooksRestore() async throws {
        let suite = "leaf-library-test-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        defer { try? FileManager.default.removeItem(at: root) }
        let url = try fixture(root: root, title: "Saved book")
        let reader = ReaderModel(restorePosition: false, defaults: defaults)
        reader.load(url)
        try await waitForImport(reader)
        reader.selectChapter(1)
        reader.load(root.appendingPathComponent("invalid.epub"))
        try await waitForImport(reader)
        XCTAssertNotNil(reader.error)
        XCTAssertEqual(reader.library.count, 1)
        reader.load(url)
        try await waitForImport(reader)
        XCTAssertEqual(reader.chapterIndex, 1)
        XCTAssertEqual(reader.library.count, 1)
    }

    @MainActor
    private func waitForImport(_ reader: ReaderModel) async throws {
        for _ in 0..<500 {
            if !reader.isImporting { return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Book import timed out")
    }

    private func fixture(root: URL, title: String) throws -> URL {
        try FileManager.default.createDirectory(at: root.appendingPathComponent("META-INF"), withIntermediateDirectories: true)
        let files = [
            "mimetype": "application/epub+zip",
            "META-INF/container.xml": "<container><rootfiles><rootfile full-path=\"book.opf\"/></rootfiles></container>",
            "book.opf": "<package xmlns:dc=\"http://purl.org/dc/elements/1.1/\"><metadata><dc:title>\(title)</dc:title><dc:creator>Author</dc:creator></metadata><manifest><item id=\"a\" href=\"a.xhtml\" media-type=\"application/xhtml+xml\"/><item id=\"b\" href=\"b.xhtml\" media-type=\"application/xhtml+xml\"/></manifest><spine><itemref idref=\"a\"/><itemref idref=\"b\"/></spine></package>",
            "a.xhtml": "<html><body><h1>One</h1><p>First chapter.</p></body></html>",
            "b.xhtml": "<html><body><h1>Two</h1><p>\(String(repeating: "A longer passage for pagination. ", count: 200))</p></body></html>"
        ]
        for (path, text) in files { try Data(text.utf8).write(to: root.appendingPathComponent(path)) }
        let archive = root.appendingPathComponent("book.epub")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.currentDirectoryURL = root
        process.arguments = ["-q", "-r", archive.path, "mimetype", "META-INF", "book.opf", "a.xhtml", "b.xhtml"]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        return archive
    }
}
