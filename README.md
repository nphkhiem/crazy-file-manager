# Crazy File Manager

Crazy File Manager is a native macOS utility for finding the accessible files and folders that consume the most storage. It is designed to be calm, explicit, and safe: scanning is local, user-initiated, and metadata-only.

## Status

The application is under active development. It can run an explicit, local, metadata-only Home Folder scan, show incremental largest-item results, and present completed results as a lazily paged expandable Tree with bottom-up accessible folder totals. Active scans can be paused, resumed, or cancelled; incomplete candidates are removed after cancellation, failure, or a previous crash without replacing the last completed Tree. Filesystem mutation features are being added as independently tested vertical slices.

## Requirements

- macOS Sonoma 14 or newer
- Xcode with Swift 6 support

## Open and run

Open `CrazyFileManager.xcodeproj` in Xcode and run the `CrazyFileManager` scheme.

The checked-in Xcode project is generated from `project.yml`. When changing target layout, regenerate it with XcodeGen:

```sh
xcodegen generate
```

## Verification

Lint the Swift source:

```sh
xcrun swift-format lint --recursive --parallel --strict \
  CrazyFileManager CrazyFileManagerTests CrazyFileManagerUITests
```

Run all tests:

```sh
xcodebuild test \
  -project CrazyFileManager.xcodeproj \
  -scheme CrazyFileManager \
  -destination 'platform=macOS,arch=arm64'
```

Build a universal release:

```sh
xcodebuild build \
  -project CrazyFileManager.xcodeproj \
  -scheme CrazyFileManager \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  ARCHS='arm64 x86_64' \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_ALLOWED=NO
```

## Privacy and safety direction

- No automatic scan on launch
- Launch cleanup removes only incomplete local snapshot candidates
- No file-content inspection
- No accounts, analytics, telemetry, or automatic crash upload
- No root access, privileged helper, shell command, or permanent-delete fallback
- Rename and Move to Trash will require immediate identity and policy revalidation

## License

Licensed under the Apache License, Version 2.0. See `LICENSE`.
