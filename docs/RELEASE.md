# Release and source handoff

## Current status

The project builds a native macOS app and has automated reader tests. Source export is prepared for review. Copyright attribution and commercial buyer license terms have not been supplied; this repository cleanup does not grant a license to Leaf's original code. Do not describe the review archive as an approved commercial release until those terms and the optional runtime's licensing have been reviewed.

## Buyer setup

Install Xcode command-line tools with Swift 5.9+ on macOS 13+. Run `swift test`, then `bash scripts/package.sh`. Launch `dist/Leaf.app` rather than its bare executable so app resources, preferences, Keychain identity, and Dock icon resolve correctly. The default build targets the build machine's architecture. Local Kokoro additionally requires native Apple Silicon and macOS 14+; Mac voices remain available on supported Intel builds.

Python 3.9+ is needed only for the source-export and audit helper scripts. End users obtain the optional local speech runtime through Settings.

## Branding and signing

Set your application name, bundle identifier, version, and build in `packaging/Info.plist`. Review displayed product strings, Application Support folder naming, and the generated icon in `packaging/generate-icon.swift`. Keep a stable bundle identifier for upgrades: changing it creates a new preference/Keychain identity.

The default script ad-hoc signs for local development. With your own Developer ID certificate installed, build using:

```sh
SIGNING_IDENTITY="Developer ID Application: Your Company (TEAMID)" bash scripts/package.sh
```

This enables hardened runtime and timestamped signing. `REGISTER_APP=0` skips local Launch Services registration for CI. Never include signing certificates, private keys, Apple credentials, or Keychain exports in the source sale.

For direct app distribution, complete Apple's notarization and stapling workflow and test the final artifact on a clean Mac. These credentials and publishing steps are intentionally not embedded in the project. App Store submission is a separate project: the current app is not sandboxed and optionally downloads executable runtime components.

## Source archive

```sh
python3 scripts/package-source.py
```

Without `LICENSE`, this produces `dist/Leaf-source-review.zip`. Supply your approved copyright and buyer terms in `LICENSE`, then:

```sh
python3 scripts/package-source.py --require-license
```

The sale export is `dist/Leaf-source.zip`. It contains source, tests, scripts, packaging metadata, current buyer documentation, and `SOURCE_MANIFEST.json` with file hashes. Git history, application data, books, installed models, build caches, signed binaries, and internal historical QA notes are excluded by an allowlist. The exporter also rejects symlinked external files and common private-key patterns. This is an additional packaging check, not a replacement for reviewing every delivered file.

Validate the actual exported archive by extracting it into a clean folder and running its tests and package script there. Share the archive itself, not a copy of the entire workspace.

## Dependency review

Read `DEPENDENCIES.md` and `THIRD_PARTY_NOTICES.md`. The original Swift source, Kokoro weights, runtime libraries, Python distribution, and hosted services are separate licensing surfaces. Preserve upstream notices and verify the terms applicable to your intended source and binary distribution. The optional runtime includes GPL, LGPL, and MPL components; do not market the entire product/runtime as Apache-only or MIT-only.

The checked-in dependency snapshot records the qualified installed environment, not all future vulnerabilities. Rerun the inventory and vulnerability scan after package updates. Before shipping a new version, exercise import, per-book restoration, native/local narration, pause/resume, sentence navigation, display wake protection, library removal, missing files, provider changes, and cancellation on the macOS/architectures you plan to support.
