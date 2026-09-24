# Implementation tickets

Tickets are tracked locally because no external tracker was specified. Statuses describe this repository, not an external issue system.

| ID | Priority | Ticket | Status | Depends on |
| --- | --- | --- | --- | --- |
| LEAF-001 | P0 | Native word callbacks and UTF-16 source mapping | Implemented; local smoke check passed | — |
| LEAF-002 | P0 | Continuous narration and cancellation state machine | Implemented; local smoke check passed | 001 |
| LEAF-003 | P0 | TextKit pagination and reflow anchoring | Implemented | 001 |
| LEAF-004 | P0 | Import EPUB package and spine safely | Implemented, text-first scope | — |
| LEAF-005 | P1 | Native reading window and controls | Implemented; initial visual QA passed | 002–004 |
| LEAF-006 | P1 | Gemini/Zephyr word-alignment qualification | Adapter implemented; live quality measurements open | 001 |
| LEAF-007 | P1 | Opt-in OpenRouter playback and cancellation | Implemented experimentally; live-account QA open | 006 |
| LEAF-008 | P1 | Remember books, bookmarks, and reading position | Minimal position persistence implemented; full library open | 004 |
| LEAF-009 | P2 | Rich EPUB rendering and navigation fidelity | Open | 004 |
| LEAF-010 | P1 | macOS release qualification and distribution | In progress | 001–005 |
| LEAF-011 | P1 | OpenRouter key, model, and voice settings | Implemented; Keychain live save QA open | 007 |
| LEAF-012 | P2 | Cloud resilience and audio cache | Open | 006–007 |

## LEAF-001 — Native word synchronization

Use installed Mac voices and real engine callbacks. Highlight the exact callback range in the rendered text. Acceptance: starting at a non-first page yields correct offsets; emoji, accents, smart quotes, and repeated words do not shift ranges; out-of-bounds and stale ranges are ignored. Implementation: `ReadingSession.swift`, `ReaderModel.swift`. Tests: `ReadingSessionTests`.

## LEAF-002 — Playback lifecycle and automatic progression

Read the current page, continue across pages and chapters, pause immediately, resume the existing utterance. Cancellation must invalidate callbacks before stopping speech. Acceptance: rapid Read/Pause does not create competing voices; manual navigation and opening a book cancel playback; cancelled completion cannot turn a page; pause at a chapter boundary cannot advance until resumed; final chapter ends cleanly. Automated state checks are included; real-engine timing QA remains required.

## LEAF-003 — Pagination that follows the words

Use identical TextKit typography for measurement and display. Acceptance: page ranges cover each UTF-16 unit exactly once; resizing and font changes keep the current spoken word visible; automatic turns do not restart speech. Tests: `PaginationTests`. Long-word clipping and diverse writing systems need broader device QA.

## LEAF-004 — Text-first EPUB importer

Read container.xml, OPF metadata/manifest/spine, and XHTML in spine order. Skip non-linear resources, scripts, hidden content, navigation, and empty chapters. Never extract untrusted archive paths onto disk. Apply archive/resource/text limits. Acceptance: valid test EPUB opens; malformed XML and missing resources surface readable errors; encoded traversal is rejected. Current limitation: encrypted resources (including font obfuscation), publisher styling, images, and non-XML HTML are unsupported.

## LEAF-005 — Quiet native reading interface

Implement the design in `DESIGN.md`: contents sidebar, spacious page, green word highlight, page counters, Read/Pause/Resume, installed voice picker, text sizing, pace, and keyboard shortcuts. Acceptance: usable at 850×600 and larger; content does not clip at supported font sizes; controls have accessibility labels; import errors preserve the existing book.

## LEAF-006 — Cloud alignment spike

The implementation now uses OpenRouter TTS with two word-following modes: estimated (the default; word positions approximated from the audio's measured speech span, word length, and punctuation) and timestamped transcription that matches normalized transcript words to source UTF-16 ranges with validated full coverage, timestamp bounds, and ordering. A timestamp mismatch or failure falls back to clearly labeled estimated positions with a visible notice and skips further timing requests for that chapter. Tests cover Unicode, repeated words, missing words, invalid times, estimated spans, and request/response contracts. A short live Gemini/Zephyr sample now generates and decodes successfully after the PCM fix. Remaining acceptance: measure boundary error on at least 20 passages (punctuation, numbers, abbreviations, accents, emoji, chapter boundaries), target median under 100 ms and 95th percentile under 250 ms for the timestamped mode, and compare estimated and transcription-based approaches against forced alignment. No live accuracy or latency claim has been established. Treat cloud highlighting as experimental until these checks pass.

## LEAF-007 — Optional cloud narration

Implemented: selected model/voice requests, sentence chunks, bounded two-chunk lookahead prefetch, in-memory audio, friendly HTTP errors, player-clock highlighting, pause/resume, provider/book/navigation cancellation, and no silent local fallback. Click-to-seek restarts narration at a clicked word or sentence, backward or forward, for cloud and Mac voices. Remaining acceptance requires a live account: paused player cannot advance highlights; seek/book changes discard late results; chunk and chapter continuation work; model errors are actionable. Persistent cache and retry policy moved to 012. No paid requests were executed during implementation.

## LEAF-008 — Library and persistence

Persist imported books or security-scoped bookmarks, chapter ID plus UTF-16 location, voice, text size, and pace. Acceptance: relaunch restores the same word after reflow; missing books are recoverable; recent-books list supports removal. Minimal implementation: the last book is stored as a security-scoped bookmark plus chapter and page (text size included), and relaunch continues there; the app also saves on close. Still open: word-level restore after reflow, recoverable missing books, a recent-books list, and pace persistence.

## LEAF-009 — EPUB fidelity

Support EPUB navigation labels, language metadata, images/alt text, headings/emphasis, links, footnotes, RTL/CJK, and font-obfuscated EPUBs. Decide whether to extend attributed text or adopt WebKit while preserving canonical text offsets. Fixed-layout EPUB and DRM need explicit product decisions. Acceptance: a representative EPUB 2/3 fixture collection renders and narrates in correct order.

## LEAF-010 — Release qualification

Build a runnable `.app`; test import and actual speech on macOS; verify pause/resume, page/chapter advance, resize, and cancellation; verify keyboard and VoiceOver; then add icon, signed distribution, notarization, and release instructions. Acceptance: automated suite passes, manual matrix is recorded with failures, app launches from Finder, no developer tools are required to run the distributed artifact. Local ad-hoc packaging is included; distribution signing is not configured.

## LEAF-011 — OpenRouter settings

Implemented secure key entry and Keychain save/remove, provider selector, Gemini/Zephyr default, speech-model picker plus editable model ID, refresh from the speech catalog, voice selection, preview, persistent preferences, and optional word timing with a selectable timing model. Saving a key selects OpenRouter. Acceptance: saved keys never enter logs/UserDefaults/project files; no placeholder is displayed as a real credential; invalid model/key errors are clear; actual preview works. UI and mocked request checks are available; real credential save/preview still require the user's key.

## LEAF-012 — Cloud reliability

Add bounded disk caching with text/model/voice/timing-version cache keys; retry only appropriate failures with explicit cost/cancellation semantics; strengthen number/abbreviation and multilingual alignment; expose useful latency diagnostics without book text or credentials. Acceptance: interrupted sessions leave no stale playback, retries cannot create duplicate paid work without a clear policy, and a cache hit preserves exact source mapping.
