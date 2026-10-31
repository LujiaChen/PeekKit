#!/bin/bash
set -euo pipefail
SOURCE_DIR="$(cd "$(dirname "$0")" && pwd -P)"
DESTINATION="${1:-$SOURCE_DIR/.build/PeekKit.app}"
if [[ -e "$DESTINATION" ]]; then echo "Destination exists: $DESTINATION" >&2; exit 1; fi
mkdir -p "$DESTINATION/Contents/MacOS" "$DESTINATION/Contents/Resources"
WORK_DIR="${PEEKKIT_BUILD_DIR:-$SOURCE_DIR/.build/intermediates}"
mkdir -p "$WORK_DIR"
WORK_DIR="$(cd "$WORK_DIR" && pwd -P)"
export CLANG_MODULE_CACHE_PATH="$WORK_DIR/ModuleCache"
IDENTITY="${PEEKKIT_SIGN_IDENTITY:--}"
SIGN_FLAGS=(--timestamp=none)
if [[ "$IDENTITY" == "Developer ID Application:"* ]]; then SIGN_FLAGS=(--options runtime --timestamp); fi
SDK="$(xcrun --sdk macosx --show-sdk-path)"
COMMON=(-I "$SOURCE_DIR/Vendor/LibArchive" -O -swift-version 5 -sdk "$SDK" -target arm64-apple-macosx14.0)
xcrun swiftc "${COMMON[@]}" -module-name PeekKit -parse-as-library "$SOURCE_DIR"/Sources/*.swift -o "$DESTINATION/Contents/MacOS/PeekKit"
for KIND in Folder Markdown; do
  EXTENSION="$DESTINATION/Contents/PlugIns/PeekKit${KIND}Preview.appex"
  mkdir -p "$EXTENSION/Contents/MacOS" "$EXTENSION/Contents/Resources"
  if [[ "$KIND" == Folder ]]; then
    SOURCES=(FolderAnalysis FolderAnalysisModel FolderAnalysisView AnalysisExport LocalFilePolicy FolderEntry FolderModel PreviewPayload FileInspection FileInspectorView ArchiveReader ArchiveBrowser FolderBrowser MarkdownDocument PreviewViewController MarkdownContent PreviewController)
    DEFINES=(-D FOLDER_EXTENSION)
  else
    SOURCES=(FolderAnalysis LocalFilePolicy MarkdownDocument PreviewProvider)
    DEFINES=(-D MARKDOWN_EXTENSION)
  fi
  FILES=(); for NAME in "${SOURCES[@]}"; do FILES+=("$SOURCE_DIR/Sources/$NAME.swift"); done
  xcrun swiftc "${COMMON[@]}" "${DEFINES[@]}" -module-name "PeekKit${KIND}Preview" -parse-as-library -application-extension "${FILES[@]}" -Xlinker -e -Xlinker _NSExtensionMain -o "$EXTENSION/Contents/MacOS/PeekKit${KIND}Preview"
  cp "$SOURCE_DIR/Resources/${KIND}-Info.plist" "$EXTENSION/Contents/Info.plist"
  cp "$SOURCE_DIR/Resources/"preview.* "$SOURCE_DIR/Resources/static-renderer.js" "$SOURCE_DIR/Resources/code-highlight.js" "$SOURCE_DIR/Resources/Vendor/"* "$EXTENSION/Contents/Resources/"
  cp "$SOURCE_DIR/Vendor/LibArchive/COPYING" "$EXTENSION/Contents/Resources/LibArchive-Headers-LICENSE.txt"
  codesign --force --sign "$IDENTITY" "${SIGN_FLAGS[@]}" --entitlements "$SOURCE_DIR/Resources/Extension.entitlements" "$EXTENSION"
done
cp "$SOURCE_DIR/Resources/App-Info.plist" "$DESTINATION/Contents/Info.plist"
cp "$SOURCE_DIR/Resources/"preview.* "$SOURCE_DIR/Resources/static-renderer.js" "$SOURCE_DIR/Resources/code-highlight.js" "$SOURCE_DIR/Resources/Welcome.md" "$SOURCE_DIR/Resources/Vendor/"* "$DESTINATION/Contents/Resources/"
cp "$SOURCE_DIR/Vendor/LibArchive/COPYING" "$DESTINATION/Contents/Resources/LibArchive-Headers-LICENSE.txt"
xcrun swift "$SOURCE_DIR/Tools/MakeIcon.swift" "$WORK_DIR/PeekKit.iconset"
iconutil -c icns "$WORK_DIR/PeekKit.iconset" -o "$DESTINATION/Contents/Resources/AppIcon.icns"
codesign --force --sign "$IDENTITY" "${SIGN_FLAGS[@]}" "$DESTINATION"
codesign --verify --deep --strict "$DESTINATION"
echo "Built: $DESTINATION"
