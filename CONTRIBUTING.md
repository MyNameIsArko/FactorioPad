# Contributing

Fork the repository and create a branch for your change. Run commands from the project folder.

## Set up and test

Install [uv](https://docs.astral.sh/uv/getting-started/installation/), then prepare the Python environment:

```sh
uv sync
```

For companion changes, run:

```sh
uv run python Tests/test_package_ipa.py
uv run python Tests/test_companion.py
```

For iOS changes, you need a Mac with Xcode 26+ and Mac Factorio at `/Applications/factorio.app`.
Use Factorio 2.0.77 for testing. Other versions are untested and are not guaranteed to work.
Run `uv run bash Tools/build_ipa.sh --prepare-only`, then open `FactorioPad.xcodeproj` in Xcode.
Run `uv run bash Tests/run_tests.sh` before submitting iOS changes.

## Open a pull request

1. Keep the change focused on one issue.
2. Push your branch and open a pull request.
3. Explain what changed and how you tested it.

Include screenshots for interface changes. Do not commit Factorio game files, personal IPAs, or account data.

For GitHub releases, see [RELEASING.md](RELEASING.md).
