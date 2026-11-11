# Leaf

A native macOS EPUB reader built with SwiftUI and AppKit. Leaf supports installed Mac voices, optional offline Kokoro narration, and optional OpenRouter speech. The Swift app has no third-party Swift package dependencies.

## Features

- A native reading interface with adjustable text and fullscreen listening.
- A recent-books library, bookmarks, and saved reading and narration positions.
- Read aloud with Mac voices, optional offline Kokoro voices, or OpenRouter.
- Word and sentence highlighting, click-to-narrate, and dictionary lookup.

## Build and run

Requirements: macOS 13 or later and Swift 5.9 or later with Xcode command-line tools. The optional local voice requires an Apple Silicon Mac, macOS 14+, 8 GB RAM, and 4 GB available disk space for initial setup.

```sh
git clone https://github.com/searchrome/leaf.git
cd leaf
swift run Leaf
swift test
bash scripts/package.sh
open dist/Leaf.app
```

The package script creates a signed `.app` with its icon and local-voice resources. Its default ad-hoc signature is intended for local development. See [release preparation](docs/RELEASE.md) for Developer ID signing, source export, and app distribution checks.

## Reading

- Open an unencrypted EPUB with **Open a book** or Command-O. A short original sample book is included.
- **Library** or Command-L reopens previous books. Files remain in their original locations.
- Space starts, pauses, or resumes narration. Left/Right moves by sentence during narration and by page when idle. The page buttons always navigate pages.
- Click a word or sentence to narrate from there. F5 toggles the fullscreen listening view.
- Select text to bookmark it, use **Look Up**, or open **Ask AI**. Bookmarks are stored per book.
- **Reading settings** controls text size, provider, voice, narration pace, and highlighting.

Leaf saves the current book, chapter, and UTF-16 text position. It checkpoints narration every two seconds and saves immediately on pause or normal quit. After relaunch, Read aloud starts at the saved sentence; window resizing preserves the text position. Narration and voice previews prevent automatic display/system sleep until paused, stopped, or finished.

## Voice providers

| Provider | Setup | Book-text processing | Highlight timing |
| --- | --- | --- | --- |
| Mac voice | Choose an installed voice | On this Mac | Native speech callbacks |
| Local model | Download and prepare Kokoro in Settings | On this Mac after setup | Estimated locally |
| OpenRouter | Supply your own API key and choose a model/voice | Sent to OpenRouter and its providers | Local estimates or optional online transcription |

**Local Kokoro:** Setup installs a private Python runtime, the pinned Kokoro model, and 28 American/British English voices in `~/Library/Application Support/Leaf/LocalKokoro`. No Homebrew or system Python installation is required. Setup can be cancelled/retried and generates test speech before marking the model ready. Settings provides voice preview, repair, and download removal. Narration works offline after setup; the worker communicates through private pipes and opens no server port. Model inference uses MLX; its English text-processing dependencies also install PyTorch through spaCy's dependency chain. See the [dependency audit](docs/DEPENDENCIES.md) and [upstream notices](docs/THIRD_PARTY_NOTICES.md).

**OpenRouter:** Keys are stored in macOS Keychain, never in project files or UserDefaults. Saving a key selects OpenRouter. Model availability and supported voices depend on the service; use **Refresh models** or enter a model ID manually. Speech generation uses account credits. **Audio timestamps** makes an additional paid transcription request; when timing fails or differs from the source, playback uses clearly labeled estimates. Estimated word/sentence timing may drift. Preview uses fixed sample text rather than book text. Leaf never silently switches speech providers.

**Dictionary lookup:** macOS Dictionary is tried first. If no definition is available, the optional online fallback sends the selected passage and nearby context through OpenRouter. This is separate from the selected speech provider and requires a saved key.

## Chat about a passage

Select book text and choose **Ask AI**, **Chat About Selected Text** from the context menu, or the Reading menu. An iMessage-style popup shows the selected passage as the first bubble, followed by your questions on the right and AI replies on the left. The conversation automatically scrolls to the latest message; the question box and prompt tags stay at the bottom. It uses your saved OpenRouter key; **Reading settings → Passage chat → Chat model ID** changes the model independently of your narration provider. The default is GLM-5.3 Flash (`z-ai/glm-5.3-flash`).

Click **Summarize**, **Simplify**, **Key points**, or **Give an example** above the question box to send a prepared question immediately. Hover over a tag to see its full question. Tags are disabled while a reply is being prepared.

**Listen** on an answer reads it using your selected Mac, local Kokoro, or OpenRouter voice and pace. **Stop listening** stops answer playback. Opening chat stops book narration. Closing the popup cancels the request, stops audio, and clears the conversation. Failed or cancelled questions remain in the input so you can retry. Chat is not saved across popup sessions.

Chat sends the selected passage and conversation to OpenRouter and its providers when you ask; it does not send the rest of the book. Usage is billed to your account. Cloud answer narration also sends the reply text for speech generation. AI answers may be inaccurate. Selections are limited to 20,000 UTF-16 text units, questions to 8,000, and conversations to 20 completed questions; start a new chat when the limit is reached.

## Tests and local runtime qualification

The ordinary suite uses generated EPUB fixtures and mocked cloud requests. It does not need a key, download models, or make paid API requests.

The optional hardware integration test downloads/prepares Kokoro in Leaf's actual Application Support directory, generates audio, and checks cancellation/restart:

```sh
LEAF_VERIFY_LOCAL_KOKORO=1 swift test --filter LocalKokoroTests/testFullSetupOfflineWorkerAndLocalNarration
```

## Current limitations

EPUB rendering is text-first. Publisher CSS/images, fixed layouts, DRM/encrypted resources, complete EPUB navigation, and additional local languages are not implemented. Book progress is approximate. App Store sandboxing, distribution notarization, and a full accessibility/device qualification matrix remain release work.

## Source archive

To create an archive containing source, tests, build scripts, license, and contributor documentation:

```sh
python3 scripts/package-source.py --require-license
```

The exporter writes `dist/Leaf-source.zip` with a SHA-256 file manifest. It excludes Git history, build products, installed runtimes, books, caches, credentials, and historical internal notes.

## Contributing and support

Bug reports and focused pull requests are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) for development, testing, and reporting guidance. Report bugs through [GitHub Issues](https://github.com/searchrome/leaf/issues); for sensitive reports, follow [SECURITY.md](SECURITY.md).

## License

Leaf's original source code, sample book, and generated icon are available under the [MIT License](LICENSE). Optional downloaded runtimes, models, and libraries retain their own licenses; see [third-party notices](docs/THIRD_PARTY_NOTICES.md).

## Project documentation

- [Architecture and file guide](docs/ARCHITECTURE.md)
- [Dependency usage and audit](docs/DEPENDENCIES.md)
- [Third-party notices](docs/THIRD_PARTY_NOTICES.md)
- [Release preparation](docs/RELEASE.md)
