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

Large-scale (up to five-million-item) performance and resilience tests are skipped by default and run only when explicitly requested, since they take tens of minutes. Run them locally with:

```sh
TEST_RUNNER_RUN_STRESS_BENCHMARK=1 xcodebuild test \
  -project CrazyFileManager.xcodeproj \
  -scheme CrazyFileManager \
  -destination 'platform=macOS,arch=arm64' \
  -only-testing:CrazyFileManagerTests/SQLiteScanSnapshotIndexPerformanceTests \
  -only-testing:CrazyFileManagerTests/SQLiteScanSnapshotIndexTests
```

CI runs the smoke-scale subset of these tests on every push and pull request as part of the regular `build-and-test` job. The full stress-scale suite runs only on manual dispatch of the `stress-benchmark` job from the Actions tab, uploading its `.xcresult` as a build artifact.

## Privacy and safety direction

- No automatic scan on launch
- No file-content inspection
- No accounts, analytics, telemetry, or automatic crash upload
- No root access, privileged helper, shell command, or permanent-delete fallback
- Rename and Move to Trash will require immediate identity and policy revalidation
- Rename and Move to Trash ship disabled in public releases until independent security review is accepted and resolved

See `PRIVACY.md` for the full privacy statement and `SECURITY.md` for the security policy and threat model.

## Scan cache lifecycle

- Launch cleanup removes crash-leftover candidate scans independently of the last completed snapshot.
- A completed snapshot is presented only after its required scope, schema, completion time, and exact 24-hour expiry metadata pass validation. Expired data is removed while the app is running and is never shown as current.
- Invalid required metadata, a failed SQLite integrity check, an incompatible schema, or SQLite corruption triggers one bounded reconstruction attempt. Reconstruction replaces only the configured database and its exact rollback-journal, WAL, and shared-memory companions; operational SQLite errors such as busy, I/O, permission, or disk failures are reported without destructive reconstruction.
- Clear Scan Data explicitly removes the completed snapshot before expiry. If removal fails, the saved results remain visible with path-free failure feedback.

## License

Licensed under the Apache License, Version 2.0. See `LICENSE`.
