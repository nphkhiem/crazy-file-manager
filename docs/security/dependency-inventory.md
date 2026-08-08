# Dependency inventory

Crazy File Manager has **zero third-party runtime dependencies**. Everything the shipped application links against is an Apple system framework or system library. This inventory also lists the two third-party components used only in CI, since they do execute against this repository's contents even though they never ship inside the app.

Verified by a repo-wide `import` audit across `CrazyFileManager/`, `CrazyFileManagerTests/`, and `CrazyFileManagerUITests/`, and by reading `project.yml`'s `dependencies:` block.

## Runtime dependencies (ship inside the app)

| Dependency | Purpose | Source | License | Version policy | Vulnerability-review status |
|---|---|---|---|---|---|
| Foundation | Core types, file system access, JSON | Apple SDK | Apple SDK license | Tracks the Xcode/SDK version pinned in CI (`macos-latest` runner's default toolchain) | Patched via macOS/Xcode updates; outside this project's direct control |
| AppKit | Native window/table/outline-view chrome | Apple SDK | Apple SDK license | Same as above | Same as above |
| SwiftUI | Declarative UI layer | Apple SDK | Apple SDK license | Same as above | Same as above |
| Observation | `@Observable` state (session/view-model layer) | Apple SDK | Apple SDK license | Same as above | Same as above |
| CryptoKit | Ed25519 signature verification (update metadata and artifact integrity), SHA-256 hashing | Apple SDK | Apple SDK license | Same as above | Same as above |
| `libsqlite3.tbd` | The persisted scan-cache database engine | System library (`project.yml:30-31`) | Public domain (SQLite) | Tracks the macOS-provided system SQLite version | Patched via macOS updates; outside this project's direct control |

Development/test-only frameworks (never ship in the Release app): `Testing` (Swift Testing, unit tests), `XCTest` (UI tests) — both Apple SDK, same policy as above.

## CI-only dependencies (never ship in the app, but execute in the build/release pipeline)

| Dependency | Purpose | Source | License | Version policy | Vulnerability-review status |
|---|---|---|---|---|---|
| `gitleaks-action` | Secret scanning on every CI run | GitHub Marketplace Action (`gitleaks/gitleaks-action`) | MIT | Pinned to a specific commit SHA, not a floating tag — updated deliberately, not automatically | Widely used, actively maintained; pinning to a SHA is this project's own mitigation against a compromised future release |
| `dependency-review-action` | Flags newly introduced dependencies with known vulnerabilities on pull requests | Official GitHub Action (`actions/dependency-review-action`) | MIT | Pinned to a specific commit SHA | Maintained directly by GitHub. Confirmed in CI (not assumed): with zero dependency manifest files of any kind, this repository's Dependency Graph is not populated, so the action currently fails outright with "Dependency review is not supported on this repository" rather than gracefully reporting nothing to review. The job is marked `continue-on-error: true` as a result, so it cannot block merges while structurally unable to function — it remains a forward-looking gate that will need re-verifying once a real dependency (and a supported manifest) is ever proposed |
| `attest-build-provenance` | Publishes a Sigstore-signed provenance attestation for each release artifact, tying it back to the exact workflow run and source commit that built it | Official GitHub Action (`actions/attest-build-provenance`) | MIT | Pinned to a specific commit SHA | Maintained directly by GitHub; uses GitHub's built-in OIDC/Sigstore integration, no external credentials required |

## Policy for adding a new dependency

Any future third-party dependency (runtime or CI-only) must be added to this table with its purpose, source, license, and an explicit vulnerability-review note before the pull request that introduces it merges. `dependency-review-action` (above) enforces this at the CI level for anything GitHub's dependency graph can see; this table is the human-readable record of record.
