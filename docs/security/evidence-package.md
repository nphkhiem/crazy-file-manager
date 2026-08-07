# Independent review evidence package

This is the entry point for an independent reviewer. It links every category of evidence to its concrete source rather than restating it. All linked evidence was verified against real, current source at the time it was written — not carried forward from an earlier claim.

## Security

- Threat model: `docs/security/threat-model.md` — filesystem confidentiality/integrity, stale-target substitution, link behavior, malicious names, cache disclosure, cloud synchronization, update compromise, dependency risk, plus explicitly accepted risk (no App Sandbox, no permanent-delete path).
- `SECURITY.md` — supported versions, private vulnerability reporting, response expectations, safe disclosure.
- Dependency inventory: `docs/security/dependency-inventory.md` — zero third-party runtime dependencies; two CI-only Actions, both pinned to a commit SHA.
- Mutation safety matrix: `docs/security/mutation-safety-matrix.md` — every Rename/Trash safety guarantee mapped to its proving test, plus one honestly-documented test-infrastructure gap.
- Entitlements and private-API audit: this ticket's Task 4 (see `hands_off/current-progress.md`'s dated entry for the exact grep evidence) — zero shell execution, zero private API usage, a deliberately empty entitlements file, Hardened Runtime already enabled for both build configurations.
- Rename/Trash public-release gate: `RestrictionPolicy.capability(for:releaseGateActive:)` and `ReleaseGate.swift` — both mutation features ship disabled in the public release build until this evidence package's review is accepted and resolved (see `PublicReleaseGateUITests` for end-to-end proof).

## Privacy

- `PRIVACY.md` — the full public privacy statement, reconciled against verified behavior including the one network request the app can make.
- Diagnostics audit: `docs/security/diagnostics-audit.md` — no logging framework, no `print` in shipped code, no crash/analytics SDK, the one network request carries no scan data.

## Update integrity

- Metadata signature verification: `CrazyFileManager/Domain/UpdateMetadataVerifier.swift`, proven by `UpdateMetadataVerifierTests.swift` (tampered payload, missing signature, malformed envelope, incompatible format/system version, replayed-version-is-not-an-error).
- Artifact integrity verification (added this ticket): `CrazyFileManager/Infrastructure/Networking/FoundationUpdateArtifactIntegrityVerifier.swift`, proven against published FIPS 180-4 SHA-256 test vectors (`FoundationUpdateArtifactIntegrityVerifierTests.swift`) and against a genuinely tampered real downloaded file (`UpdateCheckSessionTests.swift`'s real-verifier tests).

## Accessibility

- Ticket 15 ("Accessible adaptive production interface"): keyboard operability, focus restoration, VoiceOver labeling, adaptive layout down to the declared 900x600 minimum, Reduce Motion/Transparency/Increase Contrast, large-result-set keyboard traversal. Evidence: `KeyboardOperabilityUITests.swift`, `FocusRestorationUITests.swift`, `VoiceOverLabelingUITests.swift`, `AdaptiveLayoutUITests.swift`, `LargeResultSetKeyboardUITests.swift`, and the thirteen acceptance criteria checked with file:line evidence in the resolved `.scratch/crazy-file-manager/issues/15-accessible-adaptive-production-interface.md`.

## Performance and scale

- Ticket 14 ("Million-item performance and resilience"): a synthetic lazy scanner proving real memory/latency bounds at one-million and five-million-item scale, non-destructive query indexes, and a manually-dispatched `stress-benchmark` CI job. Evidence: `SQLiteScanSnapshotIndexPerformanceTests.swift`, the resolved `.scratch/crazy-file-manager/issues/14-million-item-performance-resilience.md`, and the `stress-benchmark-results` CI artifact from the last manual run.

## Migration and recovery

- Crash-leftover candidate cleanup, corruption reconstruction, and write-failure rollback, proven at both small and large (200,000-item) scale: `SQLiteScanSnapshotIndexTests.swift` (Tickets 04, 08, 14).
- Non-destructive schema migrations (v5 through v7, including the index-only v6 migration and the generated-column v7 fix) preserve existing data across every migration path — proven by golden-master query-result-identity tests in the same file.

## Release engineering

- CI: `.github/workflows/ci.yml` — `build-and-test` (lint, static analysis, unit tests, unsigned universal Release build), `secret-scan` (gitleaks), `dependency-review` (pull requests), and `release` (tag push or manual dispatch: archive, export, Developer ID sign + notarize + staple only if credentials are configured, SHA-256 checksum always).
- **Known, explicitly documented gap**: this repository does not currently have Developer ID signing or notarization credentials configured. The release pipeline is real, working code, but has not yet produced a genuinely Developer-ID-signed, notarized artifact — see `README.md`'s CI section and this ticket's design doc (`.scratch/crazy-file-manager/designs/16-security-reviewed-release-candidate-design.md`) for the explicit scope decision behind this.

## What this evidence does not claim

This package is evidence assembled *for* an independent reviewer, not a substitute for one. In particular:

- No third party has yet reviewed this codebase's security posture. That is precisely why Rename and Move to Trash ship disabled in the public release build (see above) — the safest default until that review happens.
- No release artifact produced by this repository has yet been genuinely Developer-ID-signed or notarized, for the reason stated above.
