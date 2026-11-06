import ReaderCore

enum Demo {
    static let book = Book(title: "A quieter kind of reading", author: "Welcome to Leaf", chapters: [
        Chapter(id: "welcome", title: "A little room for a good book", text: """
        A little room for a good book

        There is a particular pleasure in opening a book when the rest of the world has grown quiet. A chair by the window. A little afternoon light. A sentence that asks for nothing except your attention.

        Leaf is a place for that kind of reading. Open an EPUB, find your page, and settle in. When you would rather listen, press Read aloud. The voice begins on the page in front of you, and a small green highlight follows each spoken word.

        You do not have to keep turning pages. As the story continues, Leaf moves with it, from page to page and chapter to chapter. Press Pause whenever you need a moment. Press Resume when you are ready to return.

        The default voice belongs to your Mac. Your book stays on this computer, and reading aloud does not require an account or an internet connection. You can choose another installed voice or adjust the pace in Reading settings.

        Try resizing this window while the voice is reading. The page can change its shape, but your place stays anchored to the words. A long word, a curly quotation mark, even a café on a rainy afternoon: the highlight follows the text itself.

        This little introduction has a second chapter so you can try continuous reading before opening your own book. Leave the voice running, and it will take you there.

        Outside the window, a branch moved in the wind. Somewhere a kettle clicked off. There was time for another page.
        """),
        Chapter(id: "next", title: "One more page", text: """
        One more page

        And here we are. The next chapter arrived without a click.

        Good tools should leave room for the thing you came to do. For a reader, that means clear type, comfortable space, and a voice that knows where you are.

        Use the arrows below to browse pages yourself. Choosing another page or chapter pauses the voice, so you can explore at your own pace. Read aloud will then begin at the top of that page.

        Now open a book of your own. There is always another story waiting.
        """)
    ])
}
