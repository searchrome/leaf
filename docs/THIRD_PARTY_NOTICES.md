# Third-party notices and runtime licenses

Leaf has no third-party Swift packages. Apple frameworks and system tools are provided by macOS. The source review archive contains Leaf integration code, configuration, and tests; it does not contain downloaded speech weights, Python, uv binaries, or Python site-packages. Optional downloads retain their own upstream licenses. Leaf's original code needs its own owner-approved buyer license.

## Optional local speech

| Component | Role | Upstream license/source |
| --- | --- | --- |
| Kokoro 82M by hexgrad | Speech model | [Apache 2.0 model card](https://huggingface.co/hexgrad/Kokoro-82M) |
| MLX-community Kokoro conversion | Pinned MLX weights and voices | [Model repository](https://huggingface.co/mlx-community/Kokoro-82M-bf16) |
| kokoro-mlx by Soroush Yousefpour | Python inference implementation | [MIT license](https://github.com/gabrimatic/kokoro-mlx/blob/main/LICENSE) |
| Apple's MLX | Apple Silicon inference | [MIT license](https://github.com/ml-explore/mlx/blob/main/LICENSE) |
| Misaki by hexgrad | English text/phoneme processing | [Apache 2.0 license](https://github.com/hexgrad/misaki/blob/main/LICENSE) |
| eSpeak NG | English pronunciation fallback library/data | [GPL 3.0 or later](https://github.com/espeak-ng/espeak-ng/blob/master/COPYING) |
| espeakng-loader | Downloads/distributes the eSpeak shared library | [Package source and bundled library](https://github.com/thewh1teagle/espeakng-loader) |
| phonemizer-fork | Calls pronunciation backends | [GPL metadata and upstream links](https://pypi.org/project/phonemizer-fork/) |
| num2words | Number pronunciation | [LGPL license](https://github.com/savoirfairelinux/num2words/blob/master/COPYING) |
| spaCy and en_core_web_sm | English linguistic analysis | [spaCy MIT license](https://github.com/explosion/spaCy/blob/master/LICENSE), [model release](https://github.com/explosion/spacy-models/releases/tag/en_core_web_sm-3.8.0) |
| uv | Managed runtime/package installer | [Apache 2.0 or MIT](https://github.com/astral-sh/uv/blob/main/docs/reference/policies/license.md) |
| Managed CPython | Executes the local worker | [CPython license](https://docs.python.org/3/license.html), [python-build-standalone notices](https://github.com/astral-sh/python-build-standalone) |

The model's Apache license does not describe every runtime component. In particular, the GPL pronunciation libraries and LGPL number processing need separate review when choosing source/binary distribution terms. The loader's wrapper metadata does not replace eSpeak's library license. Keep the actual installed distributions' LICENSE, COPYING, NOTICE, and license-directory files when redistributing them. The package metadata inventory lists additional transitive libraries and declared licenses; it is not a complete legal analysis of bundled native code or model data.

## Hosted services

OpenRouter and its model providers are optional hosted services accessed using the user's key. API access, billing, model availability, data handling, and service terms are separate from a purchase of Leaf's source. No API account or usage credits are supplied in the source package. See [OpenRouter](https://openrouter.ai/) for its current service terms.

## Original assets

The leaf icon is drawn from repository-native AppKit code in `packaging/generate-icon.swift`. The included sample book is in `DemoBook.swift`. No downloaded book, stock icon, commercial font file, or paid image asset is included in the source export. The interface uses system-installed fonts.
