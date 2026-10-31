# Installation and troubleshooting

## Source release status

PeekKit currently provides source for Apple Silicon/macOS 14+. Build it locally with [these steps](BUILDING.md). The default signing is ad-hoc; the source preview does **not** include a Developer ID–signed, notarized download. Local success is not a guarantee that Gatekeeper or Quick Look will accept a copied development build on another Mac.

## Enable Finder previews

1. Build PeekKit and move `.build/PeekKit.app` into Applications. Keep one installed copy; move an older version somewhere recoverable first.
2. Open PeekKit once. Its **Quick Look Settings** button opens the extension settings.
3. Enable **PeekKit Folder** and **PeekKit Markdown**. On recent macOS releases, this is under **System Settings → General → Login Items & Extensions → Quick Look**. Older versions may place extension settings elsewhere.
4. In Finder, select a normal folder or Markdown file and press **Space**. Close/reopen Quick Look after changing extension settings.

The app's **Preview…** button offers a standalone reader. Normal Finder use does not require the main app to stay open.

## If Finder shows the system's default preview

- Confirm that both PeekKit extensions are enabled and the app remains in Applications.
- Close duplicate development copies and keep a single installed copy.
- Reopen Finder's preview after installing/enabling an extension. Signing/registration issues may require a local rebuild.
- Test a readable ordinary folder first. Trash, network volumes and cloud-provider locations may have different system access behavior. Folder Quick Look in Trash is not guaranteed.

Do not disable Gatekeeper, SIP or the extension sandbox to install PeekKit. If a build is rejected, use a local build or wait for a signed/notarized release.

## Uninstall

Disable PeekKit's two Quick Look extensions, quit its standalone app, then move PeekKit.app to Trash. No daemon or login item needs removal.

Apple's settings reference: [Login Items & Extensions](https://support.apple.com/guide/mac-help/mtusr003/mac).

## 1.3 archive previews

The existing PeekKit Folder extension also declares ZIP, TAR, gzip and bzip2 types. Formats and limits: [ARCHIVES.md](ARCHIVES.md). Close Quick Look after updating; avoid duplicate development copies. A standalone preview is useful to distinguish parser errors from system extension selection. Source-only/ad-hoc builds are not notarized. No paid account is needed for the build. See [validation scope](VALIDATION-1.3.md) before relying on Finder integration on a different Mac.
