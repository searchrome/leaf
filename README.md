# Leaf

A native macOS EPUB reader with local read-aloud, word or sentence highlighting, automatic page/chapter progression, and pause/resume.

## Run

Requires macOS 13+ and Swift 5.9+ (Xcode command-line tools). No package dependencies.

```sh
swift run Leaf
```

Build a Finder-launchable app:

```sh
bash scripts/package.sh
open dist/Leaf.app
```

Use **Open a book** or Command-O for an unencrypted EPUB. Press **Read aloud** to start from the current page. Space pauses/resumes; arrow keys navigate. A two-chapter sample is included to try narration immediately.

## What is implemented

Native SwiftUI/AppKit UI, text-first EPUB import, installed Mac voices, TextKit pagination, speech-callback highlighting, continuous narration, pause/resume, font sizing, pace and voice selection. Word positions use shared UTF-16 offsets; no estimated timing loop. This uses Apple's native speech API instead of spawning `say`, so real speech-unit callbacks are available. It remains local and uses no cloud AI model.

## OpenRouter voices

Open **Reading settings** (the text-size button at the top right). Paste your OpenRouter key into the secure field and click **Save key**. This stores it in macOS Keychain and selects OpenRouter as the provider. Choose a speech model and voice, then use **Preview voice** or return to the book and press **Read aloud**.

The cloud default is `google/gemini-3.8-flash-lite-tts` with `Zephyr`; the earlier `google/gemini-3.1-flash-tts-preview` remains selectable. Gemini is requested as PCM and wrapped in a 24 kHz, 16-bit mono WAV for macOS playback and transcription; other speech models use MP3. **Refresh models** loads OpenRouter's current speech catalog and supported voices. You can also enter a model ID and supported voice manually. Provider, model, voice, highlighting, and word-following choices persist. The API key is never written into project files or UserDefaults.

A live Gemini/Zephyr sample has been generated with the saved key and decoded by macOS; broader playback and timing accuracy qualification remains open. With word highlighting enabled, highlight granularity is chosen in Settings (**Word by word** or **Whole sentences**) and applies to both voice types. Word following defaults to **Fast word follow**: each short passage plays as soon as its audio is ready, and word positions are estimated from the audio's measured speech span, word length, and punctuation, so highlights may drift; sentence highlighting merges each sentence's word spans. Choosing **Audio timestamps** in Settings transcribes each audio chunk through OpenRouter (default timing model `openai/whisper-1`), and validated word timestamps drive highlights from the player's clock. Speech generation always consumes account credits and sends text/audio to OpenRouter and its providers; the timestamp mode adds a transcription request that also consumes credits. If timestamps are unavailable or differ from the source, playback continues with a visible notice and clearly labeled estimates instead, and further timing requests are skipped for the rest of that chapter. You can turn highlighting off to listen without alignment; pages then advance at chunk boundaries. Preview generates a fixed short sample without transcription or book text.

The app never silently switches back to a Mac voice. Local speech remains available in the provider selector and requires no key or network connection. See the [OpenRouter speech API](https://openrouter.ai/docs/guides/overview/multimodal/tts) and [timestamped transcription API](https://openrouter.ai/docs/api/api-reference/stt/create-transcription) used by the adapter.

This first version renders chapter text and paragraphs. Publisher CSS/images, persistent library/positions, full EPUB navigation, encrypted resources, and notarized distribution are not included yet.

## Design and implementation plan

- [Design and synchronization architecture](docs/DESIGN.md)
- [Prioritized tickets and acceptance criteria](docs/TICKETS.md)
- [Verification record](docs/VERIFICATION.md)

```sh
swift test
```
