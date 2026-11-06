# Architecture

Leaf is a Swift Package with a native executable target (`Leaf`) and a reusable reader target (`ReaderCore`). There are no external Swift package dependencies. Optional local speech is a separate Python worker; cloud speech uses URLSession.

## Source map

| File/module | Responsibility |
| --- | --- |
| `LeafApp.swift` | App entry, commands, window scene, Dock icon delegate |
| `ReaderView.swift`, `ReaderTheme.swift` | Main reader layout and shared colors |
| `PageText.swift` | AppKit text view, selections, bookmark interactions, click-to-seek |
| `ListeningExperience.swift`, `DictionaryLookupView.swift` | Listening and lookup presentation |
| `ReaderModel.swift` | Main-actor reading, navigation, narration coordination, persistence checkpoints |
| `ReadingPosition.swift`, `BookLibrary.swift`, `ReaderAnnotations.swift` | Saved positions, recent books, text bookmarks |
| `ReadingSettingsView.swift`, `SpeechSettings.swift` | Settings and Keychain-backed cloud credentials |
| `PlaybackActivity.swift` | Paired display/system idle-sleep holds during playback |
| `CloudNarrator.swift` | Generated audio playback for both OpenRouter and local Kokoro |
| `LocalKokoro.swift` | Hardware checks, optional download/install, readiness and removal |
| `LocalKokoroWorker.swift`, `LocalCommand.swift` | Persistent worker protocol and cancellable setup subprocesses |
| `Resources/LocalKokoro.py` | Pinned model download, benchmark, offline WAV generation |
| `Resources/LocalKokoro.requirements.txt` | Qualified Python package versions |
| `DemoBook.swift` | Included sample text |
| `ReaderCore/EPUBImporter.swift` | Bounded archive reads, OPF spine import, XML text extraction |
| `ReaderCore/Pagination.swift` | TextKit pagination using shared reader typography |
| `ReaderCore/ReadingSession.swift`, `SentenceNavigation.swift` | UTF-16 position mapping, generation tokens, sentence destinations |
| `ReaderCore/CloudSpeech.swift` | Speech HTTP requests, audio normalization, estimates and transcript alignment |

## Position and cancellation invariants

All stored text offsets use UTF-16, matching NSString, TextKit, and AVSpeechSynthesizer callbacks. Imported chapter text is shared by pagination and speech. A page is only a range over that text; stored text positions survive repagination.

Each narration start creates a generation token. Stale callbacks, cancelled tasks, and old utterance completions cannot advance the active reader. Pause freezes progression; completion racing with pause is deferred until Resume. Explicit page/sentence navigation replaces the active speech destination while preserving whether it was paused.

Native Mac speech uses speech-unit callbacks. Generated audio plays bounded passages using AVAudioPlayer. Its clock drives word/sentence estimates or validated transcription timestamps. One next passage is prefetched after playback begins; prepared audio is held in a bounded in-memory cache.

## Runtime and data boundaries

The local worker receives JSON lines containing request ID, passage, and voice. It returns JSON containing request ID and base64 WAV audio, or an error. It loads local weights once and handles requests serially. Pending requests are failed on process termination or cancellation, and generation has a timeout. There is no HTTP listener. Local inference disables Hugging Face online lookups after setup.

The app's preferences hold provider selection, visual settings, recent-book metadata, reading positions, and bookmarks. The OpenRouter key is in Keychain under the current bundle identifier plus `.openrouter`. Default builds preserve `local.leaf.reader.openrouter`; a differently branded bundle gets its own service. Original book files are referenced, not copied. Downloaded local runtimes/models live in Application Support and are never included in source exports.

## Extending the code

Add import/alignment/state behavior in ReaderCore where possible. Keep native UI actions in Leaf. A new generated voice provider should return audio and optional source timing through the existing preparation/playback path, preserving cancellation and pause behavior. When changing local packages or model revisions, update the requirements, rerun the local integration test, and refresh both dependency reports.
