import Foundation
import Testing

@testable import CrazyFileManager

@Suite("Foundation Scan Scope Authorizer")
struct FoundationScanScopeAuthorizerTests {
  @Test
  func givenBuiltInScopeSelections_whenDescribed_thenNormalizedVolumeEvidenceIsCaptured()
    throws
  {
    let homeInput = URL(filePath: "/Users/tester/../tester", directoryHint: .isDirectory)
    let homeLocation = URL(filePath: "/Users/tester", directoryHint: .isDirectory)
    let diskInput = URL(filePath: "/", directoryHint: .isDirectory)
    let reader = StubScanScopeResourceReader(
      metadataByLocation: [
        homeInput: ScanScopeResourceMetadata(
          canonicalLocation: homeLocation,
          volumeRoot: diskInput,
          volumeIdentifier: "INTERNAL-UUID",
          isInternal: true,
          isReadOnly: false,
          isRemovable: false
        ),
        diskInput: ScanScopeResourceMetadata(
          canonicalLocation: diskInput,
          volumeRoot: diskInput,
          volumeIdentifier: "INTERNAL-UUID",
          isInternal: true,
          isReadOnly: false,
          isRemovable: false
        ),
      ]
    )
    let authorizer = FoundationScanScopeAuthorizer(
      homeDirectoryURL: homeInput,
      internalDiskURL: diskInput,
      resourceReader: reader
    )

    let home = authorizer.describe(.homeFolder)
    let disk = authorizer.describe(.entireInternalDisk)

    #expect(
      home.availability
        == .available(
          ScanScope(
            kind: .homeFolder,
            location: homeLocation,
            volumeIdentity: ScanVolumeIdentity(rawValue: "INTERNAL-UUID"),
            volumeCharacteristics: ScanVolumeCharacteristics(
              isInternal: true,
              isReadOnly: false,
              isRemovable: false
            )
          )
        )
    )
    #expect(
      disk.availability
        == .available(
          ScanScope(
            kind: .entireInternalDisk,
            location: diskInput,
            volumeIdentity: ScanVolumeIdentity(rawValue: "INTERNAL-UUID"),
            volumeCharacteristics: ScanVolumeCharacteristics(
              isInternal: true,
              isReadOnly: false,
              isRemovable: false
            )
          )
        )
    )
  }

  @Test
  func givenRelocatedCustomBookmark_whenDescribed_thenCurrentLocationIsUsed()
    throws
  {
    let lastKnownLocation = URL(
      filePath: "/Volumes/Archive",
      directoryHint: .isDirectory
    )
    let currentLocation = URL(
      filePath: "/Volumes/Renamed Archive",
      directoryHint: .isDirectory
    )
    let reference = CustomScopeReference(
      displayName: "Archive",
      lastKnownLocation: lastKnownLocation
    )
    let reader = StubScanScopeResourceReader(
      metadataByLocation: [
        currentLocation: ScanScopeResourceMetadata(
          canonicalLocation: currentLocation,
          volumeRoot: currentLocation,
          volumeIdentifier: "ARCHIVE-UUID",
          isInternal: false,
          isReadOnly: true,
          isRemovable: true
        )
      ]
    )
    let authorizer = FoundationScanScopeAuthorizer(
      homeDirectoryURL: URL(filePath: "/Users/tester"),
      internalDiskURL: URL(filePath: "/"),
      resourceReader: reader,
      bookmarkResolver: StubCustomScopeBookmarkResolver(
        resolvedLocation: currentLocation
      )
    )

    let description = authorizer.describe(.custom(reference))

    #expect(
      description.availability
        == .available(
          ScanScope(
            kind: .custom,
            location: currentLocation,
            volumeIdentity: ScanVolumeIdentity(rawValue: "ARCHIVE-UUID"),
            volumeCharacteristics: ScanVolumeCharacteristics(
              isInternal: false,
              isReadOnly: true,
              isRemovable: true
            )
          )
        )
    )
  }

  @Test
  func givenWhitespaceVolumeIdentity_whenDescribed_thenScopeIsUnsupported()
    throws
  {
    let location = URL(
      filePath: "/Volumes/Unknown",
      directoryHint: .isDirectory
    )
    let reader = StubScanScopeResourceReader(
      metadataByLocation: [
        location: ScanScopeResourceMetadata(
          canonicalLocation: location,
          volumeRoot: location,
          volumeIdentifier: "   ",
          isInternal: nil,
          isReadOnly: nil,
          isRemovable: nil
        )
      ]
    )
    let authorizer = FoundationScanScopeAuthorizer(
      homeDirectoryURL: location,
      internalDiskURL: URL(filePath: "/"),
      resourceReader: reader
    )

    let description = authorizer.describe(.homeFolder)

    #expect(description.availability == .unsupported(location: location))
  }

  @Test
  func givenUnavailableCustomBookmark_whenDescribed_thenScopeIsDisconnected()
    throws
  {
    let lastKnownLocation = URL(
      filePath: "/Volumes/Offline",
      directoryHint: .isDirectory
    )
    let reference = CustomScopeReference(
      displayName: "Offline",
      lastKnownLocation: lastKnownLocation
    )
    let authorizer = FoundationScanScopeAuthorizer(
      homeDirectoryURL: URL(filePath: "/Users/tester"),
      internalDiskURL: URL(filePath: "/"),
      resourceReader: StubScanScopeResourceReader(metadataByLocation: [:]),
      bookmarkResolver: FailingCustomScopeBookmarkResolver()
    )

    let description = authorizer.describe(.custom(reference))

    #expect(
      description.availability
        == .disconnected(lastKnownLocation: lastKnownLocation)
    )
  }

  @Test
  func givenPreparedCustomScope_whenLeaseFinishesRepeatedly_thenAccessIsReleasedOnce()
    async throws
  {
    let location = URL(
      filePath: "/Volumes/Archive",
      directoryHint: .isDirectory
    )
    let reference = CustomScopeReference(
      displayName: "Archive",
      lastKnownLocation: location
    )
    let resourceAccess = StubSecurityScopedResourceAccess()
    let authorizer = FoundationScanScopeAuthorizer(
      homeDirectoryURL: URL(filePath: "/Users/tester"),
      internalDiskURL: URL(filePath: "/"),
      resourceReader: StubScanScopeResourceReader(
        metadataByLocation: [
          location: ScanScopeResourceMetadata(
            canonicalLocation: location,
            volumeRoot: location,
            volumeIdentifier: "ARCHIVE-UUID",
            isInternal: false,
            isReadOnly: false,
            isRemovable: true
          )
        ]
      ),
      bookmarkResolver: StubCustomScopeBookmarkResolver(
        resolvedLocation: location
      ),
      resourceAccess: resourceAccess
    )

    let preparation = authorizer.prepare(.custom(reference))
    let prepared = try #require(preparation.preparedScope)
    prepared.accessLease.finish()
    prepared.accessLease.finish()

    #expect(resourceAccess.startedLocations == [location])
    #expect(resourceAccess.stoppedLocations == [location])
  }

  @Test
  func givenPersistedCustomBookmark_whenPrepared_thenAccessStartsBeforeMetadataPreflight()
    throws
  {
    let location = URL(
      filePath: "/Volumes/Archive",
      directoryHint: .isDirectory
    )
    let reference = CustomScopeReference(
      displayName: "Archive",
      lastKnownLocation: location
    )
    let resourceAccess = StubSecurityScopedResourceAccess()
    let authorizer = FoundationScanScopeAuthorizer(
      homeDirectoryURL: URL(filePath: "/Users/tester"),
      internalDiskURL: URL(filePath: "/"),
      resourceReader: AccessRequiredScanScopeResourceReader(
        location: location,
        resourceAccess: resourceAccess
      ),
      bookmarkResolver: StubCustomScopeBookmarkResolver(
        resolvedLocation: location
      ),
      resourceAccess: resourceAccess
    )

    let preparation = authorizer.prepare(.custom(reference))
    let prepared = try #require(preparation.preparedScope)
    prepared.accessLease.finish()

    #expect(resourceAccess.startedLocations == [location])
    #expect(resourceAccess.stoppedLocations == [location])
  }

  @Test
  func givenCustomMetadataPreflightFails_whenPrepared_thenStartedAccessIsReleased() {
    let location = URL(
      filePath: "/Volumes/Offline",
      directoryHint: .isDirectory
    )
    let reference = CustomScopeReference(
      displayName: "Offline",
      lastKnownLocation: location
    )
    let resourceAccess = StubSecurityScopedResourceAccess()
    let authorizer = FoundationScanScopeAuthorizer(
      homeDirectoryURL: URL(filePath: "/Users/tester"),
      internalDiskURL: URL(filePath: "/"),
      resourceReader: StubScanScopeResourceReader(metadataByLocation: [:]),
      bookmarkResolver: StubCustomScopeBookmarkResolver(
        resolvedLocation: location
      ),
      resourceAccess: resourceAccess
    )

    let preparation = authorizer.prepare(.custom(reference))

    #expect(preparation.preparedScope == nil)
    #expect(resourceAccess.startedLocations == [location])
    #expect(resourceAccess.stoppedLocations == [location])
  }

  @Test
  func
    givenDisposableFolder_whenFoundationMetadataIsDescribed_thenPersistentVolumeEvidenceIsAvailable()
    throws
  {
    let location = FileManager.default.temporaryDirectory.appending(
      path: "CrazyFileManagerScopeTests-\(UUID().uuidString)",
      directoryHint: .isDirectory
    )
    try FileManager.default.createDirectory(
      at: location,
      withIntermediateDirectories: true
    )
    defer { try? FileManager.default.removeItem(at: location) }
    let authorizer = FoundationScanScopeAuthorizer(
      homeDirectoryURL: location,
      internalDiskURL: URL(filePath: "/", directoryHint: .isDirectory),
      resourceReader: FoundationScanScopeResourceReader()
    )

    let description = authorizer.describe(.homeFolder)
    let scope = try #require(description.availability.availableScope)

    #expect(!scope.volumeIdentity.rawValue.isEmpty)
    #expect(scope.location.lastPathComponent == location.lastPathComponent)
  }
}

private struct StubScanScopeResourceReader: ScanScopeResourceReading {
  let metadataByLocation: [URL: ScanScopeResourceMetadata]

  func metadata(at location: URL) throws -> ScanScopeResourceMetadata {
    guard let metadata = metadataByLocation[location] else {
      throw CocoaError(.fileNoSuchFile)
    }
    return metadata
  }
}

private struct AccessRequiredScanScopeResourceReader:
  ScanScopeResourceReading
{
  let location: URL
  let resourceAccess: StubSecurityScopedResourceAccess

  func metadata(at location: URL) throws -> ScanScopeResourceMetadata {
    guard resourceAccess.startedLocations.contains(location) else {
      throw CocoaError(.fileReadNoPermission)
    }
    return ScanScopeResourceMetadata(
      canonicalLocation: self.location,
      volumeRoot: self.location,
      volumeIdentifier: "ARCHIVE-UUID",
      isInternal: false,
      isReadOnly: false,
      isRemovable: true
    )
  }
}

private struct StubCustomScopeBookmarkResolver: CustomScopeBookmarkResolving {
  let resolvedLocation: URL

  func resolve(_ reference: CustomScopeReference) throws -> URL {
    resolvedLocation
  }
}

private struct FailingCustomScopeBookmarkResolver:
  CustomScopeBookmarkResolving
{
  func resolve(_ reference: CustomScopeReference) throws -> URL {
    throw CocoaError(.fileNoSuchFile)
  }
}

private final class StubSecurityScopedResourceAccess:
  SecurityScopedResourceAccessing,
  @unchecked Sendable
{
  private let lock = NSLock()
  private var starts: [URL] = []
  private var stops: [URL] = []

  var startedLocations: [URL] {
    lock.withLock { starts }
  }

  var stoppedLocations: [URL] {
    lock.withLock { stops }
  }

  func startAccessing(_ location: URL) -> Bool {
    lock.withLock {
      starts.append(location)
    }
    return true
  }

  func stopAccessing(_ location: URL) {
    lock.withLock {
      stops.append(location)
    }
  }
}
