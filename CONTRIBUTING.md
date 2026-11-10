# Contributing to Leaf

Bug reports, documentation improvements, and focused pull requests are welcome.
For larger changes, open an issue first to discuss the behavior and scope.
Treat other contributors respectfully and keep feedback specific and constructive.

## Development

Use macOS 13+ with Swift 5.9+ and Xcode command-line tools. Clone the repository,
then run:

```sh
swift run Leaf
swift test
REGISTER_APP=0 bash scripts/package.sh
```

The packaged app is `dist/Leaf.app`. See [README.md](README.md) for provider setup
and [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for a source guide.

The ordinary tests use generated books and mocked cloud requests. They require no
API key or model downloads. The opt-in Kokoro hardware test installs into Leaf's
actual Application Support directory; run it only when intentionally testing the
local runtime on supported hardware, using the command in the README.

## Reporting issues

Use [GitHub Issues](https://github.com/searchrome/leaf/issues). Include your macOS
version, Mac architecture, Leaf version or commit, steps to reproduce, expected
behavior, and what happened. For narration, include the provider and voice/model.
Share a minimal original or freely redistributable EPUB if a book is needed to
reproduce the issue. Remove API keys, private book text, and personal paths from
logs and screenshots. Follow [SECURITY.md](SECURITY.md) for sensitive reports.

## Pull requests

Explain the problem, resulting behavior, and how you verified it. Keep changes
focused and follow nearby Swift style. Add regression coverage for behavior
changes where practical, run `swift test`, and update documentation when setup,
privacy, limitations, or controls change. For UI or audio changes, describe any
manual checks and the macOS/hardware used. Never commit credentials, signing
materials, downloaded models, runtime environments, or copyrighted books.

Contributions to Leaf's original code are provided under the repository's
[MIT License](LICENSE). Preserve notices for any third-party code or assets and
document new dependencies in `docs/DEPENDENCIES.md` and
`docs/THIRD_PARTY_NOTICES.md`.
