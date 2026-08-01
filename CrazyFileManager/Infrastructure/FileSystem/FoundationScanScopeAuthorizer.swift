import Foundation

struct ScanScopeResourceMetadata: Equatable, Sendable {
  let canonicalLocation: URL
  let volumeRoot: URL
  let volumeIdentifier: String?
  let isInternal: Bool?
  let isReadOnly: Bool?
  let isRemovable: Bool?
}

protocol ScanScopeResourceReading: Sendable {
  func metadata(at location: URL) throws -> ScanScopeResourceMetadata
}

struct FoundationScanScopeResourceReader: ScanScopeResourceReading {
  func metadata(at location: URL) throws -> ScanScopeResourceMetadata {
    let values = try location.resourceValues(forKeys: [
      .canonicalPathKey,
      .volumeURLKey,
      .volumeUUIDStringKey,
      .volumeIsInternalKey,
      .volumeIsReadOnlyKey,
      .volumeIsRemovableKey,
    ])
    let canonicalLocation =
      values.canonicalPath.map {
        URL(filePath: $0, directoryHint: .isDirectory)
      } ?? location.standardizedFileURL
    return ScanScopeResourceMetadata(
      canonicalLocation: canonicalLocation,
      volumeRoot: values.volume ?? canonicalLocation,
      volumeIdentifier: values.volumeUUIDString,
      isInternal: values.volumeIsInternal,
      isReadOnly: values.volumeIsReadOnly,
      isRemovable: values.volumeIsRemovable
    )
  }
}

protocol SecurityScopedResourceAccessing: Sendable {
  func startAccessing(_ location: URL) -> Bool
  func stopAccessing(_ location: URL)
}

struct FoundationScanScopeAuthorizer: ScanScopeAuthorizing {
  private let homeDirectoryURL: URL
  private let internalDiskURL: URL
  private let resourceReader: any ScanScopeResourceReading
  private let bookmarkResolver: any CustomScopeBookmarkResolving
  private let resourceAccess: any SecurityScopedResourceAccessing

  init(
    homeDirectoryURL: URL,
    internalDiskURL: URL,
    resourceReader: any ScanScopeResourceReading
  ) {
    self.init(
      homeDirectoryURL: homeDirectoryURL,
      internalDiskURL: internalDiskURL,
      resourceReader: resourceReader,
      bookmarkResolver: LastKnownCustomScopeBookmarkResolver(),
      resourceAccess: FoundationSecurityScopedResourceAccess()
    )
  }

  init(
    homeDirectoryURL: URL,
    internalDiskURL: URL,
    resourceReader: any ScanScopeResourceReading,
    bookmarkResolver: any CustomScopeBookmarkResolving
  ) {
    self.init(
      homeDirectoryURL: homeDirectoryURL,
      internalDiskURL: internalDiskURL,
      resourceReader: resourceReader,
      bookmarkResolver: bookmarkResolver,
      resourceAccess: FoundationSecurityScopedResourceAccess()
    )
  }

  init(
    homeDirectoryURL: URL,
    internalDiskURL: URL,
    resourceReader: any ScanScopeResourceReading,
    bookmarkResolver: any CustomScopeBookmarkResolving,
    resourceAccess: any SecurityScopedResourceAccessing
  ) {
    self.homeDirectoryURL = homeDirectoryURL
    self.internalDiskURL = internalDiskURL
    self.resourceReader = resourceReader
    self.bookmarkResolver = bookmarkResolver
    self.resourceAccess = resourceAccess
  }

  func describe(_ selection: ScanScopeSelection) -> ScanScopeDescription {
    let location: URL
    let kind: ScanScope.Kind
    switch selection {
    case .homeFolder:
      location = homeDirectoryURL
      kind = .homeFolder
    case .entireInternalDisk:
      location = internalDiskURL
      kind = .entireInternalDisk
    case .custom(let reference):
      do {
        location = try bookmarkResolver.resolve(reference)
      } catch {
        return ScanScopeDescription(
          selection: selection,
          availability: .disconnected(
            lastKnownLocation: reference.lastKnownLocation
          )
        )
      }
      kind = .custom
    }

    let availability: ScanScopeAvailability
    do {
      let metadata = try resourceReader.metadata(at: location)
      guard
        let volumeIdentifier = metadata.volumeIdentifier,
        !volumeIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
          .isEmpty
      else {
        return ScanScopeDescription(
          selection: selection,
          availability: .unsupported(location: metadata.canonicalLocation)
        )
      }
      availability = .available(
        ScanScope(
          kind: kind,
          location: metadata.canonicalLocation,
          volumeIdentity: ScanVolumeIdentity(rawValue: volumeIdentifier),
          volumeCharacteristics: ScanVolumeCharacteristics(
            isInternal: metadata.isInternal,
            isReadOnly: metadata.isReadOnly,
            isRemovable: metadata.isRemovable
          )
        )
      )
    } catch {
      availability = .disconnected(lastKnownLocation: location)
    }
    return ScanScopeDescription(
      selection: selection,
      availability: availability
    )
  }

  func prepare(_ selection: ScanScopeSelection) -> ScanScopePreparation {
    let description = describe(selection)
    guard case .available(let scope) = description.availability else {
      return .unavailable(description)
    }

    let lease: any ScanScopeAccessLeasing
    switch selection {
    case .homeFolder, .entireInternalDisk:
      lease = NoopScanScopeAccessLease()
    case .custom(let reference):
      guard let accessLocation = try? bookmarkResolver.resolve(reference)
      else {
        return .unavailable(
          ScanScopeDescription(
            selection: selection,
            availability: .disconnected(
              lastKnownLocation: reference.lastKnownLocation
            )
          )
        )
      }
      lease = SecurityScopedResourceAccessLease(
        location: accessLocation,
        resourceAccess: resourceAccess,
        didStart: resourceAccess.startAccessing(accessLocation)
      )
    }
    return .ready(
      PreparedScanScope(
        scope: scope,
        accessLease: lease
      )
    )
  }
}

private struct LastKnownCustomScopeBookmarkResolver:
  CustomScopeBookmarkResolving
{
  func resolve(_ reference: CustomScopeReference) -> URL {
    reference.lastKnownLocation
  }
}

private struct FoundationSecurityScopedResourceAccess:
  SecurityScopedResourceAccessing
{
  func startAccessing(_ location: URL) -> Bool {
    location.startAccessingSecurityScopedResource()
  }

  func stopAccessing(_ location: URL) {
    location.stopAccessingSecurityScopedResource()
  }
}

private final class SecurityScopedResourceAccessLease:
  ScanScopeAccessLeasing,
  @unchecked Sendable
{
  private let location: URL
  private let resourceAccess: any SecurityScopedResourceAccessing
  private let didStart: Bool
  private let lock = NSLock()
  private var isFinished = false

  init(
    location: URL,
    resourceAccess: any SecurityScopedResourceAccessing,
    didStart: Bool
  ) {
    self.location = location
    self.resourceAccess = resourceAccess
    self.didStart = didStart
  }

  func finish() {
    let shouldStop = lock.withLock {
      guard !isFinished else {
        return false
      }
      isFinished = true
      return didStart
    }
    if shouldStop {
      resourceAccess.stopAccessing(location)
    }
  }
}

private struct NoopScanScopeAccessLease: ScanScopeAccessLeasing {
  func finish() {}
}
