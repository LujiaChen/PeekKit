# Contributing

Build and test on Apple Silicon using [BUILDING.md](docs/BUILDING.md) and [TESTING.md](docs/TESTING.md).

For a bug report, include macOS version, Apple chip, signing/install method, expected behavior, and a small synthetic example if possible. For size mismatches, include the analysis scope and which size metric you compared. Avoid uploading personal folders, private paths or file contents.

Pull requests should explain the visible behavior being changed and relevant validation. Keep analysis off the main actor, retain cancellation/partial-result behavior, and preserve offline operation. Changes that hydrate cloud files, follow external symlinks or add network permissions need an explicit design discussion.

Keep third-party license notices with redistributed code. Contributions are submitted under the repository's MIT license for original code.
