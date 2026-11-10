# Verification

Environment: Apple Silicon Mac, Swift 6.3.3 / Xcode 26.6. Verification date: 2026-09-24.

## Automated

`swift test`: 38 tests passed, zero failures. Coverage includes source UTF-16 offsets, stale/out-of-order callbacks, pause/resume and completion races at the pure-state level, pagination coverage/reflow anchors, EPUB fixture import and malformed/path input, cloud chunk text preservation, transcript matching/invalid timestamps, speech/model/transcription request fields, safe HTTP authentication errors, Gemini PCM-to-WAV conversion decoded by AVAudioPlayer, WAV transcription format, MP3 preservation for other models, and stage-specific provider errors with redaction. Narrator tests also verify that failed, missing, or mismatched timing preserves playable audio and switches to clearly labeled estimated word positions with a notice, that matching timing preserves highlights, and that cancellation never falls back to playback. Estimated timings are checked to span words within the measured speech window, stay ordered, and cover silent audio across the full duration; decoded-envelope anchoring (including an understated player duration) and the truncated-audio refusal are covered by loudness-envelope fixtures, and per-segment Xing/Info length headers in joined MP3 responses are checked to be removed. Sentence timings are checked to merge word spans into sentence ranges, including unterminated trailing text. Seek snapping is checked to land clicked offsets on the start of the clicked word or sentence with clamped out-of-range input, reading-position persistence is checked for a save/load round trip with corrupt or negative input rejected, and unsupported model/voice combinations are checked to be rejected locally with the supported list before any paid request is sent. OpenRouter requests in tests use a local URLProtocol stub; they do not call paid services.

`bash scripts/package.sh`: release app built and ad-hoc signed successfully, including the cloud-enabled implementation.

## Native app smoke check

Observed in the launched app: reading layout and selectable page text fit; Read aloud produced moving word highlights; Pause displayed Resume and resumed the same passage; narration turned from page 1 to page 2 automatically; changing text size while speaking reflowed pages while keeping the spoken word visible; narration continued into chapter 2; end-of-book stopped at 100%; manual chapter navigation during playback returned to idle on the destination chapter. These checks used the bundled two-chapter demo and macOS speech callbacks. They establish visual/lifecycle behavior, not measured audio/visual latency.

## Remaining qualification

The new settings were also checked in an isolated QA app to preserve the user's open book in the older process. Verified secure key field, disabled Save/Preview with no key, provider switch, a live public speech-catalog refresh, model selection updating the exact model ID, and missing-key handling opening Settings without sending book text. Gemini 3.1 / Zephyr and Whisper 1 were found in the public catalogs. No credential was entered.

Kokoro returns several joined MP3 segments, each with its own Xing header; macOS trusted the first (7.0 s of a 21.2 s response), so the player clock froze while audio continued and highlights raced ahead. With the headers removed, a cached real Kokoro response kept the player clock within 0.02 s of wall time for its full 21.2 s, and the user confirmed sentence highlighting stays in sync. Live diagnosis with the saved Keychain key reproduced HTTP 400: Gemini requires PCM and rejected the previous MP3 request. The corrected Swift client generated a fixed short Gemini 3.1 / Zephyr sample: 149,804 WAV bytes, decoded by AVAudioPlayer as 3.12 seconds. Whisper returned word timestamps, but the sample transcript did not match the source exactly. The narrator now preserves generated audio on timing failure, switches to clearly labeled estimated word positions with a visible notice, and skips further transcription requests for the rest of the chapter; regression tests verify this path. The key was read in memory and never printed or saved to project files. This was a small paid live test, not a broad timestamp-accuracy or audible UI playback qualification. Keychain save was not re-tested. Additional manual checks: a diverse EPUB collection, rapid boundary races with real audio, window resizing, keyboard/VoiceOver, older macOS versions, Bluetooth latency, and signed/notarized distribution. Click-to-seek on real audio (playing and paused, cloud and Mac voices) and relaunch position restore still need manual QA. Library positions beyond the last book are not persisted yet.

## Local Kokoro qualification — 2026-10-23

Tested on a MacBook Air M3 with 24 GB RAM and macOS 26.6.2. `LEAF_VERIFY_LOCAL_KOKORO=1 swift test` passed all 61 tests, including the real installer and local worker. The opt-in integration test downloaded the private uv/Python runtime, Kokoro weights, English phonemization dependencies, and 28 English voices into Leaf's actual Application Support directory. American and British voices produced WAV files decodable by AVAudioPlayer. Cancellation stopped an outstanding request, and a fresh request succeeded after restarting the worker. Local narration configuration uses no key and forces estimated alignment instead of cloud transcription. Regular tests cover unsupported hardware/OS/disk, partial installation state, removal, and missing-model failures.

The final warm speed check generated 5.5 seconds of speech in 0.7 seconds (7.9× real time). An independent worker run under `sandbox-exec` with `(deny network*)` first verified that a socket connection was denied, then generated a valid 3.27-second, 24 kHz WAV from local files. This establishes offline synthesis for the installed English path, not timing accuracy across arbitrary books or performance on all supported Macs.

The release app was rebuilt and ad-hoc signature verification passed. In the launched release app, Settings displayed Local model, the compatible 24 GB Mac, downloaded/ready status, benchmark, voice selection, and removal/repair controls. Preview local voice entered playback and Stop preview returned it to idle without errors. A custom ICNS Dock icon was generated and included through CFBundleIconFile. First-time setup was tested through the same installer code via XCTest; native progress/cancel presentation and a complete remove/redownload cycle still need manual qualification. Other languages and Intel Macs are not supported by this local runtime.

## Playback wake protection — 2026-10-27

Narration and voice previews now hold both `idleSystemSleepDisabled` and `idleDisplaySleepDisabled`, including preparation between passages. The initial system-only hold allowed the display to turn off while speech continued; the display flag addresses that separately. Pause, stop, completion, and reader destruction release the hold. Three playback lifecycle tests pass. A compiled smoke check using the actual PlaybackActivity class confirmed through `pmset -g assertions` that both PreventUserIdleSystemSleep and PreventUserIdleDisplaySleep are registered for the process during playback and both are released afterward. This verifies power assertions, not an override of explicit user locks or managed security policies. The release app was rebuilt and ad-hoc signed.

## Passage restoration — 2026-10-27

ReadingPosition and library entries now retain UTF-16 text positions and the last narrated sentence separately from page numbers. Repagination preserves the text anchor across startup/window sizing. Both generated narration and Mac-voice callbacks checkpoint progress within a page every two seconds; pause and normal termination save immediately. On relaunch, the reader remains idle and Read aloud starts at the saved sentence. A saved file URL backs up bookmark resolution, and an unavailable book cannot have its saved position overwritten by the introductory demo.

`swift test`: 66 tests, 1 opt-in local-model test skipped, zero failures. Added integration coverage for narration-position persistence through relaunch, repeated viewport changes and library switching, manual page navigation resetting the speech anchor, older page-only saves, and preserving unavailable-book saves. Sentence-navigation and wake-protection tests now use isolated preferences. These are model-level restart tests; a physical app quit/relaunch with live audio remains a manual check.

## Source cleanup and dependency review — 2026-11-06

Split app entry, reader UI, text view, listening/lookup views, saved-position types, sample text, subprocess handling, and local worker protocol into focused files. Missing packaged local-voice resources now produce an actionable error. Reader teardown removes its notification observer and cancels owned tasks. Keychain service identity follows the app bundle identifier, preserving the existing default identifier.

The local Python package graph is pinned to the qualified installed versions. Metadata inventory contains 94 distributions. pip-audit reported no known advisories for 93 audited distributions; en-core-web-sm 3.8.0 could not be audited through PyPI. GPL/LGPL/MPL and ambiguous upstream metadata are recorded in docs/DEPENDENCIES.md and docs/THIRD_PARTY_NOTICES.md. This is not an approval of commercial licensing or a complete native-library/model vulnerability assessment.

All 66 Swift tests passed with the opt-in real local installer/generation test enabled. A source review archive was checked for valid ZIP contents, per-file SHA-256 manifest matches, absence of developer home-directory paths, and excluded runtime/build/history/private-key data. The archive was then extracted into a new temporary folder: its ordinary tests passed (66 total, one opt-in test skipped), and its own release package script built and signature-verified Leaf.app without referencing the original checkout. Buyer license/owner attribution remains to be supplied. No source archive, app, or repository has been published as part of those checks.

## Open source preparation — 2026-11-10

The repository now licenses Leaf's original code and assets under MIT, attributed
to Serdar Ozay. This supersedes the historical notes above about an outstanding
buyer license. Added contributor and security-reporting guidance, a macOS CI
workflow, and open source release instructions. Optional downloaded dependencies
retain their upstream licenses. No repository visibility or publishing change
was made by this preparation.

`swift test`: 66 tests executed, one opt-in local-runtime test skipped, zero
failures on Apple Silicon with Swift 6.3.3. The real model installer and paid
services were not exercised during this preparation.

Release packaging completed successfully, including ad-hoc signature verification
and bundled MIT/third-party notices. A limited credential-pattern scan of 55
tracked files and all seven existing commits found no matching OpenRouter keys,
GitHub tokens, AWS access-key IDs, or private-key headers. This scan does not
establish the absence of all secrets or private data. The new GitHub workflow
has been added locally and has not yet run on GitHub.
