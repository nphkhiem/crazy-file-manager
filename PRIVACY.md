# Privacy

This statement describes exactly what Crazy File Manager does and does not do with your data. Every claim below is verified against the current source, not aspirational.

## Scanning

- Scanning is local, explicit, and metadata-only. Nothing scans automatically on launch; you choose a scope (Home Folder, Entire Internal Disk, or a custom folder/volume) and start it yourself.
- The scanner reads only file and folder metadata — names, sizes, dates, kind, and filesystem identity — never file contents (`CrazyFileManager/Infrastructure/FileSystem/FoundationFileSystemScanner.swift`).
- Symbolic links are recorded as links and never followed into their targets (`FoundationFileSystemScanner.swift:239-241`, `enumerator?.skipDescendants()` on every symbolic link).
- Nothing scanned ever leaves this Mac. There is no server this application talks to for scanning, search, filtering, sorting, Rename, or Move to Trash — those features have no network code at all.

## What is stored, and for how long

- At most one completed scan is retained on disk, as a local SQLite database under `~/Library/Application Support` (`CrazyFileManager/App/AppContainer.swift:70`, `URL.applicationSupportDirectory`).
- That snapshot expires automatically 24 hours after it completes (`CrazyFileManager/Infrastructure/Snapshot/SQLiteScanSnapshotIndex.swift:1313`, `completedAt.addingTimeInterval(86_400)`) and can be cleared explicitly at any time from Settings.
- Session Activity (the record of rename/trash attempts shown in the Inspector) is kept in memory only and clears when you quit the app.

## No accounts, analytics, or telemetry

There is no account, no advertising, no analytics, no behavioral telemetry, and no automatic crash upload. There is no logging framework anywhere in the application (verified: zero `os_log`/`Logger`/`NSLog` usage, and no `print` statements in shipped code) — nothing is written to a log file, local or remote, that could later leak scanned paths or filenames.

## The one network request this app can make

Update Checks is off by default. When you enable it, or when you click "Check for Updates Now," the app sends a single unauthenticated `GET` request to a fixed metadata URL (`CrazyFileManager/Infrastructure/Networking/FoundationUpdateClient.swift`) — no query string, no custom headers, no device or user identifier, and critically, no file names, paths, or scan data of any kind, since the request carries no parameters at all. The response is a signed metadata blob verified with a pinned Ed25519 public key before anything in it is trusted (`CrazyFileManager/Domain/UpdateMetadataVerifier.swift`); if you choose to download an update artifact, its contents are hash-verified against that same signed metadata before it is ever revealed to you.

## Filesystem mutation safety

Rename and Move to Trash re-verify the target's live identity (device, inode, parent path, and volume) immediately before mutating, refuse to touch OS-protected or ambiguous (hard-linked) paths, and never permanently delete — they only move items to the system Trash. See `docs/security/mutation-safety-matrix.md` for the specific test evidence behind these claims.

## Questions

If anything here seems inconsistent with the application's actual behavior, please report it — see `SECURITY.md` for how.
