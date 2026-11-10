# Installation and troubleshooting

Requires **Apple Silicon and macOS 14+**. No paid Apple developer account is needed.
PeekKit's credential-free builds are **ad-hoc signed, not Developer ID signed or
Apple notarized**. A signature check detects changed code; an ad-hoc signature
does not establish publisher identity or guarantee Gatekeeper/Quick Look approval.

## Option A — Pre-built ZIP or DMG

Use this path when a [GitHub Release](https://github.com/LujiaChen/PeekKit/releases)
contains `PeekKit-<version>-arm64-adhoc.zip` or `.dmg`. Version 1.3.3 and later provide these assets through the automated release
workflow. Older releases, including
the original 1.3.2 source release, may contain only source; use Option B for those.
Xcode is not required for this path; the helper uses tools included with macOS.

1. Download the ZIP **or** DMG and `SHA256SUMS.txt` from the **same release**.
   In Terminal, change to your download folder and verify the chosen asset:

   ```sh
   # Replace <version> with the exact version from that release.
   shasum -a 256 'PeekKit-<version>-arm64-adhoc.zip'
   ```

   Compare the entire output digest with its filename's entry in `SHA256SUMS.txt`.
   For DMG, hash the `.dmg` instead. If you downloaded every listed asset, use
   `shasum -a 256 -c SHA256SUMS.txt`. A checksum from the same release detects
   corruption; it is not independent publisher authentication. Stop on a mismatch.

2. Extract the ZIP or mount the DMG. Close PeekKit and its Quick Look previews.
   Keep your old app temporarily somewhere recoverable, then drag the new
   **PeekKit.app** into **Applications**. Avoid keeping multiple installed copies.
   Do not run the app directly from the mounted DMG or Downloads.

3. Open Terminal in the extracted folder (ZIP) or mounted volume (DMG). Keep
   `install-app.sh` and its `Tools` folder together. **After verifying and deciding
   to trust this download**, run this one-line preparation command:

   ```sh
   bash ./install-app.sh --allow-quarantine-removal
   ```

   This validates the app, architecture, versions, both extensions and their
   sandbox entitlements **before** changing anything. It removes only
   `com.apple.quarantine` from this app, registers the two extensions and resets
   Quick Look's registration/cache. It preserves unrelated extended attributes.
   Removing quarantine skips this app's download quarantine check; it is an
   explicit trust decision, not notarization or a guarantee of safe code.

4. Open PeekKit once, then enable **PeekKit Folder** and **PeekKit Markdown**.
   On recent macOS releases: **System Settings → General → Login Items & Extensions
   → Quick Look**. Locations vary by macOS version. The app's **Quick Look Settings**
   button opens the settings page. The helper does not override your enable/disable
   choices or force-enable extensions.

5. In Finder, select an ordinary readable folder and press **Space**. Repeat with
   a Markdown file and a supported archive. Remove your temporary old copy only
   after previews work. The main app need not stay open for Finder previews.

### Diagnosis and optional re-signing

Check without changing files, registration or Quick Look caches:

```sh
bash ./install-app.sh --check-only
```

The downloaded bundle is already ad-hoc signed. **Re-signing is optional**, not
normally required. If troubleshooting a verified download on your Mac, close
PeekKit and all its previews before running:

```sh
bash ./install-app.sh --allow-quarantine-removal --resign
```

The helper signs the two extensions first and the host app last, preserving
signed entitlements and checking the resulting signatures. It does not use
`codesign --deep` for signing; `--deep --strict` is used for verification only.
It refuses a damaged signature rather than re-signing potentially altered code.
Re-download or build locally if validation fails. Signing failure can leave a
partially updated bundle; keep the temporary old copy until successful validation.

For an installation you own outside `/Applications`, specify its absolute,
canonical path (no symbolic links), for example:

```sh
bash ./install-app.sh --app "$HOME/Applications/PeekKit.app" --allow-quarantine-removal
```

`--prepare-only` validates/prepares without registering extensions or resetting
caches. `--help` lists all options. No automatic `sudo`, process killing, global
Gatekeeper changes, SIP changes or sandbox weakening are performed.

## Option B — Build from source

Install/select Xcode and its macOS SDK, then:

```sh
git clone https://github.com/LujiaChen/PeekKit.git
cd PeekKit
# For a reproducible release, check out its published tag before building.
git checkout v1.3.3
./build.sh
```

Alternatively download a source ZIP and its checksum from the release. Follow
[build instructions](BUILDING.md), move `.build/PeekKit.app` to Applications,
open it once and enable both extensions as above. Local builds default to
ad-hoc signing and need no certificate or network dependency downloads. Source
builds do not guarantee that every system will accept a development extension.
The output app must not already exist when running `build.sh`.

## If Finder shows the system's default preview

- Confirm both extensions are enabled and the app remains in Applications.
- Close/reopen Quick Look after updating. The helper prints registration paths;
  they should point inside your installed app. Extra old paths indicate duplicate
  copies to remove. The helper does not delete or unregister unrelated copies.
- If re-signing is refused because a preview is active, close it and try again.
  The helper does not forcibly restart Finder or QuickLookUIService.
- Test a readable ordinary folder first. Trash, network volumes and cloud-provider
  locations have different system access behavior; Trash previews are not guaranteed.
- If the system still rejects a trusted pre-built app, use a local source build.
  Managed Macs may have policies that this helper cannot change. Do not disable
  Gatekeeper, SIP, or the extension sandbox.

Supported formats and budgets: [ARCHIVES.md](ARCHIVES.md). PDF behavior and limits:
[PDF.md](PDF.md). Registration and signature success are separate from an actual
Finder Space-bar test; [test scope](TESTING.md) documents that boundary.

## Uninstall

Disable the two Quick Look extensions, quit PeekKit, then move PeekKit.app to
Trash. No daemon or login item needs removal.

Apple references: [Login Items & Extensions](https://support.apple.com/guide/mac-help/mtusr003/mac),
[Code Signing In Depth](https://developer.apple.com/library/archive/technotes/tn2206/).
