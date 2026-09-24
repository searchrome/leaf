# Leaf — a macOS reader that follows the voice

## Product

A quiet native reading window: warm paper, dark green controls, Georgia body text, generous margins. A narrow sidebar holds the current book and its chapters. The page header shows the chapter; the footer holds page navigation, Read aloud / Pause / Resume, voice pace, and book progress. A settings sheet holds text size, pace, the Mac/OpenRouter provider selector, secure API-key entry, model selection, voice, preview, and word-highlighting preferences. Keyboard: Command-O opens a book, Space toggles narration, arrow keys change pages.

Read aloud begins at the first character on the current visible page. The current speech unit receives a soft green background; highlights follow word by word or whole sentences, chosen in Settings. Pages follow the voice; chapters continue automatically. Pause stops audio immediately and preserves the utterance. Resume continues it. Manual navigation cancels narration and makes the destination page the next starting point. Reflow preserves the current word. At book end, narration stops and the UI says so. Changing pace or voice while playing restarts from the current word; changing them while paused returns to idle.

The first implementation is a text-first native EPUB reader for unencrypted, reflowable EPUBs. It preserves chapter order, paragraph separation, entities, and Unicode. Publisher CSS, images, footnotes, fixed layouts, and library persistence are subsequent tickets. Cloud playback has an experimental implementation pending live-account qualification. Chapter titles come from the first heading, rather than the EPUB navigation document. Progress is an approximate chapter-weighted measure, not word-weighted.

## The difficult part: authoritative word synchronization

The referenced `/Users/sozay/workspace/unitytutor/bridge/src/speech.js` starts `say` processes and estimates segment duration. A process-completion signal cannot identify the currently spoken word. Duration estimates accumulate drift, and a timer does not know when an engine pauses or pronounces punctuation differently.

Leaf uses `AVSpeechSynthesizer` with installed macOS voices, preserving the local, non-cloud default. This is a native replacement for the `say` subprocess, not a literal invocation of the CLI. Apple's delegate supplies an `NSRange` before each speech unit (usually a word). See [Apple's callback documentation](https://developer.apple.com/documentation/avfaudio/avspeechsynthesizerdelegate/speechsynthesizer(_:willspeakrangeofspeechstring:utterance:)). Callback timing is the engine's estimate at speech-unit granularity; audio-output latency, Bluetooth latency, and UI scheduling still need perceptual checks on target devices.

1. Normalize chapter text once on import. Display and speech consume the identical string.
2. TextKit paginates that text into contiguous UTF-16 ranges, using the same font and paragraph settings as the visible view.
3. Start one utterance at the visible page's chapter offset and speak through the chapter's remainder. Do not synthesize one word or one visual page at a time.
4. Translate callback range to chapter range: `absolute = utteranceStart + callback.location`.
5. Find the page containing that offset, then translate to a page-local highlight range.
6. Attach both utterance identity and a generation token. Cancellation invalidates old events before stopping the synthesizer.
7. Pause gates callbacks and completion. If chapter completion races a pause, remember it and advance only after Resume.
8. Reflow changes page ranges, never the speech text or its offsets.

Apple's speech ranges and TextKit both use UTF-16. Counting Swift Characters instead would shift highlights after emoji, combining marks, and other non-ASCII text. Temporary TextKit background attributes avoid changing line layout during highlighting.

## Optional cloud voice

Target: OpenRouter `google/gemini-3.8-flash-lite-tts`, voice `Zephyr`. [OpenRouter TTS documentation](https://openrouter.ai/docs/guides/overview/multimodal/tts) documents audio generation via `/api/v1/audio/speech`. It does not establish a word-timing contract we can use directly. Raw generated audio is insufficient for synchronized highlighting.

The implemented timing adapter generates sentence-based chunks. Word following has two modes. **Fast word follow** (the default) estimates word positions from the audio's measured speech span, per-word length, and punctuation pauses; it is deliberately approximate, with no transcription request or accuracy claim. **Audio timestamps** instead requests timestamped transcription of the generated audio (WAV for Gemini PCM, MP3 for other models), matches normalized transcript words to the exact source string, validates coverage and timestamps, and drives highlights from `AVAudioPlayer.currentTime`. [OpenRouter's transcription API](https://openrouter.ai/docs/api/api-reference/stt/create-transcription) supplies the word timestamps with `verbose_json` and `timestamp_granularities: ["word"]` on supported providers. The timestamped mode is transcription-derived alignment, not a measured forced-alignment solution. Quality and latency still need live qualification. Highlight granularity is chosen in Settings: word by word, or whole sentences formed by merging each sentence's word spans (estimated or transcribed) with no extra requests.

Adapter output is audio plus `[{ utf16Range, startSeconds, endSeconds }]`, a generation token, and source range. `CloudNarrator` snapshots configuration for a session, prefetches at most the next two chunks, cancels old tasks on seek/book/provider changes, and ignores stale responses. Pause stops the player's clock; a result arriving while paused is prepared but not played. Rate changes use the player without regenerating audio. Temporary prepared audio stays in memory; there is no persistent cache yet.

The key lives in macOS Keychain. Saving a key explicitly selects OpenRouter; generating speech occurs only on Read aloud or Preview. Preview uses fixed sample text and no transcription. Provider/model/voice choices persist in UserDefaults. API errors identify speech generation versus word timing, include the HTTP status and a bounded top-level provider message, and redact credentials and submitted content; raw provider metadata is never displayed. No automatic paid retry or silent Mac fallback occurs.

If timestamped timing is absent, nonmonotonic, or cannot match all source/transcript words, the generated audio still plays and word following switches to clearly labeled estimates for the rest of the chapter, announced by a visible notice; further transcription requests are skipped for that chapter. Estimated positions can drift, and each short passage starts a fresh estimate. Cancellation still discards preparation rather than starting playback. Readers can explicitly turn off highlighting to listen without alignment; page position then updates only at chunk boundaries. The word-following mode and timing model can be changed in Settings. The UI explains that speech uses paid OpenRouter requests, that the timestamp mode adds another, and that book text/generated audio is sent to OpenRouter and its providers.

## Verification and release gates

Automated checks cover UTF-16 mapping, invalid callback bounds, pause/resume, stale callbacks, exact page boundaries, reflow anchors, full pagination coverage, EPUB spine order and hidden text, malformed input, and archive path traversal. Manual checks must cover real speech, page/chapter transitions, rapid pause/resume, resize while speaking, opening another book mid-speech, different voices, and keyboard/VoiceOver access. Cloud needs measured alignment quality before its ticket can be closed.
