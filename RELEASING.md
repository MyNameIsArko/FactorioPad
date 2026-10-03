# Create a GitHub release

GitHub Actions builds the companions for Windows, macOS, and Linux.
The workflow needs an existing `FactorioPad-template.ipa` attached to the release.
The workflow attaches each companion archive to that release.

1. Create a draft GitHub release with `FactorioPad-template.ipa` attached.
2. In the repository, open `Actions` and select `Build companion releases`.
3. Click `Run workflow` and enter the release tag, such as `v2.0.1`.
4. Wait for all three builds to pass.
5. Publish the draft release.

The workflow creates these release files:

- `FactorioPad-Companion-Windows-x64.zip`
- `FactorioPad-Companion-macOS-arm64.zip`
- `FactorioPad-Companion-Linux-x64.tar.gz`

Publish only the game-free template and companion archives. Keep personal IPAs and Factorio game files private.
