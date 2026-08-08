# Diagnostics and privacy audit

This audit checks whether any local diagnostics, logging, or failure path could transmit or persist filenames, paths, or scan metadata unexpectedly. Every finding below was re-verified directly against the current source at audit time, not carried over from an earlier claim.

## No logging surface exists

- Zero `os_log`/`OSLog`/`Logger(`/`NSLog(` usage anywhere in `CrazyFileManager/`.
- Zero `print(` statements in shipped (non-test) source.
- Zero crash-reporting or analytics SDK integration of any kind (the only matches for "analytics"/"crashlytics"/etc. across the source tree are `PrivacySettingsView.swift`'s own text asserting their absence, not an integration).

This means there is no local log file, and no remote logging/crash/analytics endpoint, that could ever accumulate or transmit a scanned path or filename — the failure-string leak vector this audit exists to check simply has no surface to leak through.

## The one network request

The only network-capable code in the app is the update-check path (`FoundationUpdateClient`, `FoundationUpdateArtifactDownloader`). Verified directly:

- `FoundationUpdateClient.fetchMetadataEnvelope(from:)` calls `session.data(from: url)` with the fixed configured metadata URL and nothing else — no query parameters, no custom headers, no device or user identifier of any kind.
- The request only fires when the user has enabled automatic update checks (off by default, confirmed via `UserDefaultsUpdateCheckPreferencesStore`'s `defaults.bool(forKey:)` returning `false` with no prior stored value) or clicks "Check for Updates Now" explicitly.
- `FoundationUpdateArtifactDownloader.download(from:)` downloads only the URL named inside the already-signature-verified metadata blob, to the user's own Downloads folder — no additional network calls, no telemetry about the download itself.

No scan path, filename, or scan-cache content is ever constructed into a URL, header, or request body anywhere in the codebase — confirmed by inspecting every network call site directly (there are exactly two: the metadata fetch and the artifact download, both above).

## User-facing failure strings stay local

Every failure-reason string a user can see (`renameValidationMessage`, `trashValidationMessage`, `RestrictionPolicy`'s `cannotRenameReason`/`cannotTrashReason`, `downloadFailureMessage`) is plain `String` state on `ExplorerSession`/`UpdateCheckSession`, rendered directly into SwiftUI `Text` views. None of it is written to a file, logged, or included in any network request — there is no code path connecting these strings to the one network request described above, since that request carries no parameters at all.

## Conclusion

No diagnostic, logging, or failure path in this application transmits or persists filenames, paths, or scan metadata beyond the user's own local scan cache (covered separately in `docs/security/threat-model.md`'s cache-disclosure section, including its 24-hour expiry and explicit-clear mechanism).
