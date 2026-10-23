import SwiftUI

struct BookLibraryView: View {
    @ObservedObject var reader: ReaderModel
    @State private var search = ""

    private var books: [LibraryBook] {
        guard !search.isEmpty else { return reader.library }
        return reader.library.filter {
            $0.title.localizedCaseInsensitiveContains(search) || $0.author.localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Your library").font(.system(size: 28, weight: .medium, design: .serif))
                    Text("Return to a book, right where you left off.").foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") { reader.showLibrary = false }.keyboardShortcut(.cancelAction)
            }
            TextField("Search by title or author", text: $search)
                .textFieldStyle(.roundedBorder)
                .accessibilityLabel("Search library")
            if reader.library.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "books.vertical").font(.system(size: 38)).foregroundStyle(.secondary)
                    Text("Your books will feel at home here.").font(.headline)
                    Text("Open an EPUB to add it to your library.").foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if books.isEmpty {
                Text("No books match your search.")
                    .foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(books) { book in
                            HStack(spacing: 12) {
                                Button { reader.openLibraryBook(book) } label: {
                                    HStack(spacing: 15) {
                                        Image(systemName: "book.closed.fill")
                                            .font(.system(size: 26)).foregroundStyle(Color.accentColor)
                                            .frame(width: 52, height: 68)
                                            .background(Color.accentColor.opacity(0.08), in: RoundedRectangle(cornerRadius: 5))
                                        VStack(alignment: .leading, spacing: 5) {
                                            Text(book.title).font(.system(size: 17, weight: .medium, design: .serif)).lineLimit(2)
                                            Text(book.author).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                            Text(book.id == reader.currentLibraryID ? "Currently reading" : "Continue · Chapter \(book.chapterIndex + 1), page \(book.pageIndex + 1)")
                                                .font(.caption).foregroundStyle(.secondary)
                                        }
                                        Spacer(minLength: 0)
                                        Image(systemName: "arrow.right").foregroundStyle(.secondary)
                                    }
                                    .multilineTextAlignment(.leading).contentShape(Rectangle())
                                }.buttonStyle(.plain)
                                Button { reader.removeLibraryBook(book) } label: {
                                    Image(systemName: "xmark").frame(width: 26, height: 32)
                                }
                                .buttonStyle(.plain).foregroundStyle(.secondary)
                                .help("Remove from library; the EPUB file and bookmarks are kept")
                                .accessibilityLabel("Remove \(book.title) from library")
                            }
                            .padding(12)
                            .background(Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 9))
                        }
                    }
                }
            }
            HStack {
                Text("Books stay in their original file locations.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Open a book…", action: reader.openBook).disabled(reader.isImporting)
            }
        }
        .padding(28).frame(width: 600, height: 500)
        .overlay {
            if reader.isImporting {
                ZStack {
                    Color(nsColor: .windowBackgroundColor).opacity(0.94)
                    ProgressView("Opening your book…")
                }
            }
        }
        .alert("Unable to open book", isPresented: Binding(get: { reader.error != nil }, set: { if !$0 { reader.error = nil } })) {
            Button("OK") { reader.error = nil }
        } message: { Text(reader.error ?? "") }
    }
}
