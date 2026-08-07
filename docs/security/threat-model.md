# Threat model

This document covers the threats Crazy File Manager is designed to resist, and the concrete mitigation for each, cited against the real implementation. It is a living document — update it whenever a new mutation path, network call, or persisted state is added.

## 1. Filesystem confidentiality and integrity

**Threat**: the app reads more than metadata, or a bug lets a scan alter files it only meant to inspect.

**Mitigation**: the scanner requests only resource-value metadata (`FileManager.default.enumerator(at:includingPropertiesForKeys:...)`, `CrazyFileManager/Infrastructure/FileSystem/FoundationFileSystemScanner.swift:194-211`) and never opens a file for reading its contents anywhere in the codebase — confirmed by the total absence of `FileHandle`/`Data(contentsOf:)`/`String(contentsOf:)` reads of scanned files outside test fixtures. Scanning never mutates anything; only the explicit Rename and Move to Trash flows write to the filesystem, and both are covered separately below.

## 2. Stale-target substitution

**Threat**: between the moment a user chooses to rename/trash an item and the moment the mutation actually executes, the filesystem could have changed underneath it (the path now points somewhere else, a different item occupies that inode, the volume changed) — a classic time-of-check-to-time-of-use (TOCTOU) race.

**Mitigation**: `MutationPreflight.validate` (`CrazyFileManager/Application/MutationPreflight.swift`) re-reads live filesystem evidence (device identifier, inode, parent path, volume identifier) immediately before every rename or trash mutation and compares it against the `ExpectedMutationTarget` captured when the user initiated the action. Any mismatch aborts the mutation with a validation failure surfaced to the user (`renameValidationMessage`/`trashValidationMessage`) rather than silently proceeding against the wrong target. See `docs/security/mutation-safety-matrix.md` for the specific tests proving this.

## 3. Link behavior

**Threat**: a symbolic link is followed as if it were a real directory, letting a scan (or a mutation) escape its intended scope or double-count/misattribute size.

**Mitigation**: `FoundationFileSystemScanner.metadata(for:normalizedURL:)` classifies any `isSymbolicLink == true` item as `.symbolicLink` and calls `enumerator?.skipDescendants()` immediately (`FoundationFileSystemScanner.swift:239-241`) — a symbolic link is recorded as a leaf, never traversed into. Hard links are handled separately: `RestrictionPolicy.classify` marks any item with `isShared == true` as `.restricted(.highRisk)` (`RestrictionPolicy.swift:38-39`), disabling Rename and Move to Trash for it, since a hard-linked path sharing an inode with another path is exactly the kind of ambiguous-identity case Rename/Trash must not touch blindly.

## 4. Malicious or adversarial names

**Threat**: a file or folder name crafted to exploit path handling (path separators, `.`/`..`, reserved characters, extremely long names) causes a mutation to target the wrong path or corrupts the UI.

**Mitigation**: `RenameValidation.validate` (`CrazyFileManager/Application/RenameValidation.swift`) rejects empty names, names containing path separators, `.`/`..`, and platform-invalid characters, before any live filesystem check ever runs. No shell is ever invoked anywhere in this codebase (confirmed by the private-API/shell-execution audit in Task 4 — zero `Process`/`NSTask`/`system`/`popen` usage), so shell metacharacters in a name have no special meaning to this application regardless.

## 5. Cache disclosure

**Threat**: the persisted scan cache on disk becomes a source of information disclosure — it outlives the scan that created it, survives a crash, or lingers indefinitely.

**Mitigation**: at most one completed scan is retained, as a SQLite database under `~/Library/Application Support` (`CrazyFileManager/App/AppContainer.swift:73`), and it expires automatically 24 hours after completion (`SQLiteScanSnapshotIndex.swift:1313`, `completedAt.addingTimeInterval(86_400)`). Crash-leftover (never-promoted) candidate scans are removed on the next launch (`removeCrashLeftoverCandidates()`, Ticket 04/08). The cache lives only on the local disk it was created on — never transmitted, never backed up by this application, and explicitly clearable at any time from Settings. The cache database itself is not encrypted at rest beyond whatever full-disk encryption (FileVault) the user has enabled at the OS level — stated plainly here rather than silently assumed, since this app does not add its own encryption layer for a locally-scoped, short-lived, explicitly-clearable cache.

## 6. Cloud synchronization

**Threat**: moving a cloud-backed item (iCloud Drive, or a similar sync provider) to the Trash could propagate the removal to other synced devices in a way the user doesn't expect.

**Mitigation**: the trash-confirmation dialog explicitly warns "This item may sync its removal to other devices" whenever `detail.item.isCloudOnly` is true (`CrazyFileManager/Application/ExplorerSession.swift:604`, threaded into `ExplorerView`'s confirmation message), so the user is warned before confirming, not after.

## 7. Update compromise

**Threat**: an attacker who compromises the update-metadata hosting (or performs a network man-in-the-middle) tricks the app into fetching and running attacker-controlled code, or serves a stale/rollback metadata blob.

**Mitigation**: update metadata is Ed25519-signed and verified against a pinned public key baked into the app (`CrazyFileManager/Domain/UpdateMetadataVerifier.swift`, `UpdateSigningKey.pinnedPublicKeyBase64`) before any part of it is trusted — malformed JSON, an invalid/missing/tampered signature, an unsupported format version, or an incompatible minimum system version are all explicitly rejected, and a validly-signed but not-newer version resolves to `.upToDate` rather than any rejection (preventing a naive downgrade/replay from being misread as an error state a user might work around). As of this ticket, the downloaded update *artifact* itself is also hash-verified against a `artifactSHA256Hex` field carried inside that same signed payload before it is ever revealed to the user — closing the gap where only the metadata, not the actual downloaded bytes, was previously verified. The app never executes a downloaded artifact itself; it only reveals it in Finder for the user to run manually (Ticket 13's explicit out-of-scope decision: no automatic update installation).

## 8. Dependency risk

**Threat**: a compromised or vulnerable third-party dependency is pulled into the build, or the CI supply chain itself is tampered with.

**Mitigation**: this application has zero third-party runtime dependencies — everything is Apple system frameworks (Foundation, AppKit, SwiftUI, Observation, CryptoKit) plus the system `libsqlite3.tbd` (`project.yml:30-31`), confirmed by a repo-wide import audit. The only third-party code that touches this project at all is two GitHub Actions used purely in CI (`gitleaks`, `dependency-review-action`), both pinned to specific commit SHAs rather than floating tags, precisely to avoid this exact threat category applying to the CI supply chain itself. See `docs/security/dependency-inventory.md` for the full inventory.

## Explicitly accepted risk / architectural notes

- **No App Sandbox.** This app is distributed outside the Mac App Store (Developer ID), and its core function — scanning arbitrary user-chosen scopes including "Entire Internal Disk" — is fundamentally incompatible with sandboxed filesystem access without extensive sandbox-exception entitlements that would themselves need review and would not materially improve the actual security boundary here. Hardened Runtime (already enabled for both build configurations) plus the app's own metadata-only/no-privileged-helper/no-shell design is the real security boundary, not sandboxing.
- **No permanent-delete path.** The app can only move items to the system Trash, never permanently delete them, and never elevates privileges to do so (`README.md`'s existing "No root access, privileged helper, shell command, or permanent-delete fallback" claim, verified true).
- **Rename and Move to Trash ship disabled in public releases pending independent review** (Task 3 of this ticket) — an explicit, build-time-enforced acknowledgment that the mutation paths above, while designed and tested carefully, have not yet been independently reviewed, and the safest default until that review completes is for the two mutation features to be unavailable in the artifact the public actually receives.
