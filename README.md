# Leaf

A native macOS EPUB reader built with SwiftUI and AppKit. Leaf supports installed Mac voices, optional offline Kokoro narration, and optional OpenRouter speech. The Swift app has no third-party Swift package dependencies.

## Build and run

Requirements: macOS 13 or later and Swift 5.9 or later with Xcode command-line tools. The optional local voice requires an Apple Silicon Mac, macOS 14+, 8 GB RAM, and 4 GB available disk space for initial setup.

```sh
swift run Leaf
swift test
bash scripts/package.sh
open dist/Leaf.app
```

The package script creates a signed `.app` with its icon and local-voice resources. Its default ad-hoc signature is intended for local development. See [release preparation](docs/RELEASE.md) for Developer ID signing, source export, and the remaining sale/distribution decisions.

## Reading

- Open an unencrypted EPUB with **Open a book** or Command-O. A short original sample book is included.
- **Library** or Command-L reopens previous books. Files remain in their original locations.
- Space starts, pauses, or resumes narration. Left/Right moves by sentence during narration and by page when idle. The page buttons always navigate pages.
- Click a word or sentence to narrate from there. F5 toggles the fullscreen listening view.
- Select text to bookmark it or use **Look Up**. Bookmarks are stored per book.
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

## Tests and local runtime qualification

The ordinary suite uses generated EPUB fixtures and mocked cloud requests. It does not need a key, download models, or make paid API requests.

The optional hardware integration test downloads/prepares Kokoro in Leaf's actual Application Support directory, generates audio, and checks cancellation/restart:

```sh
LEAF_VERIFY_LOCAL_KOKORO=1 swift test --filter LocalKokoroTests/testFullSetupOfflineWorkerAndLocalNarration
```

## Scope and source distribution

EPUB rendering is text-first. Publisher CSS/images, fixed layouts, DRM/encrypted resources, complete EPUB navigation, and additional local languages are not implemented. Book progress is approximate. App Store sandboxing, distribution notarization, and a full accessibility/device qualification matrix remain release work.

To create a review archive containing source, tests, build scripts, and buyer documentation:

```sh
python3 scripts/package-source.py
```

The exporter excludes Git history, build products, installed runtimes, books, caches, credentials, and historical internal notes. It writes a SHA-256 file manifest. Add your approved copyright and buyer license as `LICENSE`, then use `python3 scripts/package-source.py --require-license` for the sale archive. No license for Leaf's original source has been selected by this cleanup. Third-party components retain their own licenses.

- [Architecture and file guide](docs/ARCHITECTURE.md)
- [Dependency usage and audit](docs/DEPENDENCIES.md)
- [Third-party notices](docs/THIRD_PARTY_NOTICES.md)
- [Release and buyer handoff](docs/RELEASE.md)
