# Dependency usage and audit

Audit date: 2026-11-06. This is a snapshot of the qualified runtime installed for local Kokoro, with package metadata collected without importing dependency code. The exact inventory is in [dependency-inventory.json](dependency-inventory.json); advisory results are in [dependency-vulnerabilities.json](dependency-vulnerabilities.json).

## Swift application

`Package.swift` declares no external Swift packages. Leaf links macOS frameworks for SwiftUI/AppKit, speech/audio, Keychain, Dictionary, text layout, and system activity management. EPUB import uses macOS's `/usr/bin/unzip`; fixture creation in tests uses `/usr/bin/zip`. No Electron, browser runtime, npm packages, vendored Swift library, or preinstalled Python package is required for Mac voices.

## Optional Kokoro package chain

| Dependency | Used for | Inclusion |
| --- | --- | --- |
| uv 0.9.5 | Managed Python and package installation | Downloaded on demand; archive SHA-256 is verified |
| CPython 3.12 | Worker interpreter | Downloaded privately by uv |
| kokoro-mlx 0.1.4 | Kokoro generation | Pinned Python requirements |
| mlx / mlx-metal 0.32.4 | Apple Silicon numerical inference | Transitive, pinned |
| numpy 2.5.4 / soundfile 0.14.0 | Audio samples and WAV encoding | Transitive, pinned |
| huggingface-hub 2.3.0 | Model download during setup | Transitive, pinned; offline mode during inference |
| misaki 0.9.4 with English support | English text to phonemes | Required by kokoro-mlx |
| spaCy / en_core_web_sm 3.8.0 | English tokenization and tagging | Misaki dependency plus separately hosted model wheel |
| espeakng-loader 0.2.4 / phonemizer-fork 3.3.2 | Pronunciation fallback | Misaki English dependencies; worker explicitly loads eSpeak |
| num2words 0.5.14 | Spoken numbers | Misaki English dependency |
| spaCy curated transformers / torch 2.14.1 | Dependency chain declared by Misaki's English extra | Installed transitively; Kokoro's inference itself uses MLX |

The installed environment contains **94 distributions**. These include the packages above and their declared transitive support libraries. No unused direct Swift packages were found. Large packages such as PyTorch are not direct Leaf inference dependencies, but are required by the currently declared upstream dependency graph. Removing them by hand would make the environment inconsistent. Reducing runtime size requires a separately qualified text-processing/runtime change; this cleanup does not silently remove required dependencies.

All currently qualified Python versions are pinned in `Sources/Leaf/Resources/LocalKokoro.requirements.txt`, including the explicit spaCy model wheel URL. Kokoro weights use revision `a71e4d38b236d968966a2002c4c895dbd12b1c3c`. Managed Python currently selects the available 3.12 build; the requirements pin versions rather than providing hashes for every PyPI wheel. This is more repeatable than unconstrained minimum-version resolution, but is not a fully hermetic build.

## Advisory scan

PyPA `pip-audit` queried public package vulnerability advisories for the installed environment. **93 distributions were audited with no known advisories reported.** One distribution, `en-core-web-sm` 3.8.0, was skipped because it is distributed through GitHub rather than PyPI. The checked-in JSON records that limitation. The scan does not establish absence of vulnerabilities in the model, interpreter, native libraries, app code, hosted services, or unaudited spaCy model wheel, and it becomes stale as advisories change.

## License findings

Kokoro weights are Apache 2.0, and kokoro-mlx/MLX declare MIT licenses. The full runtime also contains **GPL** components (eSpeak NG and phonemizer), **LGPL** number processing, and **MPL** components such as certifi/tqdm. Some distributions have incomplete or ambiguous metadata, including the eSpeak loader wrapper. Therefore an Apache-only/MIT-only description of the whole download would be inaccurate. Review upstream source and actual bundled notices before deciding redistribution terms; see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md). No downloaded runtime/library binaries or weights are included in the source archive.

## Refreshing the audit

Inventory the currently installed environment without executing its package code:

```sh
python3 scripts/audit-local-runtime.py --output docs/dependency-inventory.json
```

With uv installed as an audit tool, run the advisory scan (this makes public network requests containing package names and versions):

```sh
uv tool run --from pip-audit pip-audit \
  --path "$HOME/Library/Application Support/Leaf/LocalKokoro/runtime/lib/python3.12/site-packages" \
  --format json --output docs/dependency-vulnerabilities.json
```

Audit tools are development tools, not Leaf runtime dependencies. Review skipped packages and GPL/LGPL/MPL notices separately. If changing versions, update the requirements and inventory, rerun the scan, then run ordinary Swift tests plus the opt-in local model qualification before shipping.
