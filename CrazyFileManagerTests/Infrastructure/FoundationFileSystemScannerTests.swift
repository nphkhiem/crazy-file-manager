import Foundation
import Testing

@testable import CrazyFileManager

@Suite("Foundation File System Scanner")
struct FoundationFileSystemScannerTests {
  @Test
  func givenChangedRootVolume_whenScopeIsScanned_thenEnumerationFailsBeforeEmittingItems()
    async throws
  {
    let fixture = try DisposableFileSystemFixture()
    defer { try? fixture.remove() }
    try fixture.write(bytes: [0x01], to: "visible.bin")
    let scope = ScanScope(
      kind: .custom,
      location: fixture.rootURL,
      volumeIdentity: ScanVolumeIdentity(rawValue: "EXPECTED-VOLUME"),
      volumeCharacteristics: ScanVolumeCharacteristics(
        isInternal: false,
        isReadOnly: false,
        isRemovable: true
      )
    )
    let scanner = FoundationFileSystemScanner(
      batchSize: 16,
      volumeMetadataReader: StubVolumeMetadataReader(
        identitiesByName: [
          fixture.rootURL.lastPathComponent: ScanVolumeIdentity(
            rawValue: "REPLACEMENT-VOLUME"
          )
        ]
      )
    )

    let batches = await scanner.batches(for: scope)

    await #expect(throws: FileSystemScanError.scopeChanged) {
      for try await _ in batches {}
    }
  }

  @Test
  func givenForeignNestedVolume_whenScopeIsScanned_thenMountIsIssueAndDescendantsAreSkipped()
    async throws
  {
    let fixture = try DisposableFileSystemFixture()
    defer { try? fixture.remove() }
    try fixture.createDirectory("Mounted")
    try fixture.write(bytes: [0x01], to: "Mounted/inside.bin")
    try fixture.write(bytes: [0x02], to: "sibling.bin")
    let expectedIdentity = ScanVolumeIdentity(rawValue: "APPROVED-VOLUME")
    let scope = ScanScope(
      kind: .custom,
      location: fixture.rootURL,
      volumeIdentity: expectedIdentity,
      volumeCharacteristics: ScanVolumeCharacteristics(
        isInternal: false,
        isReadOnly: false,
        isRemovable: true
      )
    )
    let scanner = FoundationFileSystemScanner(
      batchSize: 16,
      volumeMetadataReader: StubVolumeMetadataReader(
        identitiesByName: [
          fixture.rootURL.lastPathComponent: expectedIdentity,
          "Mounted": ScanVolumeIdentity(rawValue: "FOREIGN-VOLUME"),
          "sibling.bin": expectedIdentity,
        ]
      )
    )
    let batches = await scanner.batches(for: scope)
    var items: [ScannedItem] = []
    var issues: [ScanIssue] = []

    for try await batch in batches {
      items.append(contentsOf: batch.items)
      issues.append(contentsOf: batch.issues)
    }

    #expect(items.map(\.name) == ["sibling.bin"])
    #expect(issues.map(\.location.lastPathComponent) == ["Mounted"])
    #expect(issues.map(\.kind) == [.volumeUnavailable])
  }

  @Test
  func givenPermissionRevocation_whenScopeIsScanned_thenAccessibleItemsAndDenialIssueAreEmitted()
    async throws
  {
    let fixture = try DisposableFileSystemFixture()
    defer { try? fixture.remove() }
    try fixture.write(bytes: [0x01], to: "accessible.bin")
    try fixture.write(bytes: [0x02], to: "revoked.bin")
    let expectedIdentity = ScanVolumeIdentity(rawValue: "APPROVED-VOLUME")
    let scope = ScanScope(
      kind: .custom,
      location: fixture.rootURL,
      volumeIdentity: expectedIdentity,
      volumeCharacteristics: ScanVolumeCharacteristics(
        isInternal: false,
        isReadOnly: false,
        isRemovable: true
      )
    )
    let scanner = FoundationFileSystemScanner(
      batchSize: 16,
      volumeMetadataReader: StubVolumeMetadataReader(
        identitiesByName: [
          fixture.rootURL.lastPathComponent: expectedIdentity,
          "accessible.bin": expectedIdentity,
        ],
        deniedNames: ["revoked.bin"]
      )
    )
    let batches = await scanner.batches(for: scope)
    var items: [ScannedItem] = []
    var issues: [ScanIssue] = []

    for try await batch in batches {
      items.append(contentsOf: batch.items)
      issues.append(contentsOf: batch.issues)
    }

    #expect(items.map(\.name) == ["accessible.bin"])
    #expect(issues.map(\.location.lastPathComponent) == ["revoked.bin"])
    #expect(issues.map(\.kind) == [.accessDenied])
  }

  @Test
  func givenVisibleAndHiddenFiles_whenScopeIsScanned_thenBothAppearInBoundedBatches()
    async throws
  {
    let fixture = try DisposableFileSystemFixture()
    defer { try? fixture.remove() }
    try fixture.write(bytes: [0x01], to: "visible.bin")
    try fixture.write(bytes: [0x02], to: ".hidden.bin")
    let scanner = FoundationFileSystemScanner(batchSize: 1)

    let batches = await scanner.batches(for: .homeFolder(fixture.rootURL))
    var names: [String] = []
    for try await batch in batches {
      #expect(batch.items.count + batch.issues.count <= 1)
      names.append(contentsOf: batch.items.map(\.name))
    }

    #expect(Set(names) == ["visible.bin", ".hidden.bin"])
  }

  @Test
  func givenSymbolicLinkCycle_whenScopeIsScanned_thenLinksRemainLeaves()
    async throws
  {
    let fixture = try DisposableFileSystemFixture()
    defer { try? fixture.remove() }
    try fixture.createDirectory("target")
    try fixture.write(bytes: [0x01], to: "target/inside.bin")
    try fixture.createSymbolicLink("link", destination: "target")
    try fixture.createSymbolicLink("target/back", destination: "")
    let scanner = FoundationFileSystemScanner(batchSize: 16)

    let items = try await fixture.collectItems(from: scanner)

    #expect(
      items.contains {
        $0.name == "link" && $0.kind == .symbolicLink
      }
    )
    #expect(
      items.filter {
        $0.location.path(percentEncoded: false).contains("/link/")
      }.isEmpty
    )
    #expect(items.contains { $0.name == "back" && $0.kind == .symbolicLink })
    #expect(
      items.allSatisfy {
        !$0.location.path(percentEncoded: false).contains("/back/")
      }
    )
  }

  @Test
  func givenPackageWithContents_whenScopeIsScanned_thenPackageAndDescendantEvidenceAreEmitted()
    async throws
  {
    let fixture = try DisposableFileSystemFixture()
    defer { try? fixture.remove() }
    try fixture.createDirectory("Sample.app/Contents")
    try fixture.write(bytes: [0x01], to: "Sample.app/Contents/payload.bin")
    let scanner = FoundationFileSystemScanner(batchSize: 16)

    let items = try await fixture.collectItems(from: scanner)
    let package = try #require(items.first { $0.name == "Sample.app" })

    #expect(package.kind == .package)
    #expect(items.contains { $0.name == "payload.bin" })
  }

  @Test
  func givenHardLinkedPaths_whenScopeIsScanned_thenBothPathsShareFilesystemIdentity()
    async throws
  {
    let fixture = try DisposableFileSystemFixture()
    defer { try? fixture.remove() }
    try fixture.write(bytes: [0x01], to: "original.bin")
    try fixture.createHardLink("linked.bin", source: "original.bin")
    let scanner = FoundationFileSystemScanner(batchSize: 16)

    let items = try await fixture.collectItems(from: scanner)
    let original = try #require(items.first { $0.name == "original.bin" })
    let linked = try #require(items.first { $0.name == "linked.bin" })

    #expect(original.fileSystemIdentity != nil)
    #expect(original.fileSystemIdentity == linked.fileSystemIdentity)
    #expect(original.hardLinkCount == 2)
    #expect(linked.hardLinkCount == 2)
  }

  @Test
  func givenCloudAndUnavailableMetadata_whenScanned_thenEvidenceIsHonest()
    async throws
  {
    let fixture = try DisposableFileSystemFixture()
    defer { try? fixture.remove() }
    try fixture.write(bytes: [0x01], to: "cloud.bin")
    try fixture.write(bytes: [0x02], to: "unavailable.bin")
    let scanner = FoundationFileSystemScanner(
      batchSize: 16,
      cloudMetadataReader: StubCloudMetadataReader(
        cloudOnlyNames: ["cloud.bin"],
        unavailableNames: ["unavailable.bin"]
      )
    )

    let batches = await scanner.batches(for: .homeFolder(fixture.rootURL))
    var items: [ScannedItem] = []
    var issues: [ScanIssue] = []
    for try await batch in batches {
      items.append(contentsOf: batch.items)
      issues.append(contentsOf: batch.issues)
    }

    let cloudItem = try #require(items.first { $0.name == "cloud.bin" })
    #expect(cloudItem.isCloudOnly)
    #expect(items.allSatisfy { $0.name != "unavailable.bin" })
    #expect(
      issues.contains {
        $0.location.lastPathComponent == "unavailable.bin"
          && $0.kind == .metadataUnavailable
      }
    )
  }

  @Test
  func givenAnEntryThatDisappearsBeforeItsMetadataIsRead_whenScanned_thenAChangedIssueIsEmitted()
    async throws
  {
    let fixture = try DisposableFileSystemFixture()
    defer { try? fixture.remove() }
    try fixture.write(bytes: [0x01], to: "stable.bin")
    try fixture.write(bytes: [0x02], to: "vanished.bin")
    let scanner = FoundationFileSystemScanner(
      batchSize: 16,
      cloudMetadataReader: StubCloudMetadataReader(
        cloudOnlyNames: [],
        unavailableNames: [],
        vanishedNames: ["vanished.bin"]
      )
    )

    let batches = await scanner.batches(for: .homeFolder(fixture.rootURL))
    var items: [ScannedItem] = []
    var issues: [ScanIssue] = []
    for try await batch in batches {
      items.append(contentsOf: batch.items)
      issues.append(contentsOf: batch.issues)
    }

    #expect(items.map(\.name) == ["stable.bin"])
    #expect(
      issues.contains {
        $0.location.lastPathComponent == "vanished.bin" && $0.kind == .changed
      }
    )
  }

  @Test
  func
    givenTwoOrdinaryFilesReportingTheSameIdentityWithoutAgreeingLinkCounts_whenScanned_thenAConsistencyIssueIsEmittedForOneOfThem()
    async throws
  {
    let fixture = try DisposableFileSystemFixture()
    defer { try? fixture.remove() }
    try fixture.write(bytes: [0x01], to: "first.bin")
    try fixture.write(bytes: [0x02], to: "second.bin")
    let scanner = FoundationFileSystemScanner(
      batchSize: 16,
      fileIdentityReader: StubFileIdentityReader(
        identifiersByName: [
          "first.bin": "shared-identity",
          "second.bin": "shared-identity",
        ]
      )
    )

    let batches = await scanner.batches(for: .homeFolder(fixture.rootURL))
    var items: [ScannedItem] = []
    var issues: [ScanIssue] = []
    for try await batch in batches {
      items.append(contentsOf: batch.items)
      issues.append(contentsOf: batch.issues)
    }

    #expect(items.count == 1)
    #expect(issues.filter { $0.kind == .consistency }.count == 1)
    #expect(
      Set(items.map(\.name) + issues.map(\.location.lastPathComponent))
        == ["first.bin", "second.bin"]
    )
  }

  @Test
  func givenAGenuineHardLink_whenScanned_thenNoConsistencyIssueIsEmitted() async throws {
    let fixture = try DisposableFileSystemFixture()
    defer { try? fixture.remove() }
    try fixture.write(bytes: [0x01], to: "original.bin")
    try fixture.createHardLink("linked.bin", source: "original.bin")
    let scanner = FoundationFileSystemScanner(batchSize: 16)

    let batches = await scanner.batches(for: .homeFolder(fixture.rootURL))
    var items: [ScannedItem] = []
    var issues: [ScanIssue] = []
    for try await batch in batches {
      items.append(contentsOf: batch.items)
      issues.append(contentsOf: batch.issues)
    }

    #expect(items.map(\.name).sorted() == ["linked.bin", "original.bin"])
    #expect(issues.isEmpty)
  }

  @Test
  func givenUnavailableDescendant_whenScannedAndIndexed_thenAncestorTotalIsIncomplete()
    async throws
  {
    let fixture = try DisposableFileSystemFixture()
    defer { try? fixture.remove() }
    try fixture.createDirectory("Partial")
    try fixture.write(bytes: [0x01], to: "Partial/known.bin")
    try fixture.write(bytes: [0x02], to: "Partial/unavailable.bin")

    let indexDirectory = FileManager.default.temporaryDirectory
      .appending(
        path: "CrazyFileManagerScannerIndexTests-\(UUID().uuidString)",
        directoryHint: .isDirectory
      )
    try FileManager.default.createDirectory(
      at: indexDirectory,
      withIntermediateDirectories: true
    )
    defer { try? FileManager.default.removeItem(at: indexDirectory) }

    let index = SQLiteScanSnapshotIndex(
      databaseURL: indexDirectory.appending(
        path: "snapshot.sqlite",
        directoryHint: .notDirectory
      )
    )
    let scanner = FoundationFileSystemScanner(
      batchSize: 1,
      cloudMetadataReader: StubCloudMetadataReader(
        cloudOnlyNames: [],
        unavailableNames: ["unavailable.bin"]
      )
    )
    let candidate = try await index.beginCandidate(
      for: .homeFolder(fixture.rootURL)
    )
    let batches = await scanner.batches(for: .homeFolder(fixture.rootURL))
    var itemCount = 0
    var issueCount = 0

    for try await batch in batches {
      itemCount += batch.items.count
      issueCount += batch.issues.count
      try await index.append(batch, to: candidate)
    }

    let snapshot = try await index.promoteCandidate(
      candidate,
      expectedItemCount: itemCount,
      expectedIssueCount: issueCount
    )
    let partial = try #require(
      snapshot.rootPage.items.first { $0.name == "Partial" }
    )

    #expect(issueCount == 1)
    #expect(partial.isDiskUsedIncomplete)
    #expect(partial.isApparentSizeIncomplete)
  }
}

private struct StubVolumeMetadataReader: VolumeMetadataReading {
  let identitiesByName: [String: ScanVolumeIdentity]
  let deniedNames: Set<String>

  init(
    identitiesByName: [String: ScanVolumeIdentity],
    deniedNames: Set<String> = []
  ) {
    self.identitiesByName = identitiesByName
    self.deniedNames = deniedNames
  }

  func volumeIdentity(at location: URL) throws -> ScanVolumeIdentity? {
    if deniedNames.contains(location.lastPathComponent) {
      throw CocoaError(.fileReadNoPermission)
    }
    return identitiesByName[location.lastPathComponent]
  }
}

private struct StubFileIdentityReader: FileIdentityReading {
  let identifiersByName: [String: String]

  func fileResourceIdentifier(at url: URL) throws -> AnyHashable? {
    identifiersByName[url.lastPathComponent].map { $0 as AnyHashable }
  }
}

private struct StubCloudMetadataReader: CloudMetadataReading {
  enum ReadError: Error {
    case unavailable
  }

  let cloudOnlyNames: Set<String>
  let unavailableNames: Set<String>
  let vanishedNames: Set<String>

  init(
    cloudOnlyNames: Set<String>,
    unavailableNames: Set<String>,
    vanishedNames: Set<String> = []
  ) {
    self.cloudOnlyNames = cloudOnlyNames
    self.unavailableNames = unavailableNames
    self.vanishedNames = vanishedNames
  }

  func isCloudOnly(at url: URL) throws -> Bool {
    if vanishedNames.contains(url.lastPathComponent) {
      throw CocoaError(.fileNoSuchFile)
    }
    if unavailableNames.contains(url.lastPathComponent) {
      throw ReadError.unavailable
    }
    return cloudOnlyNames.contains(url.lastPathComponent)
  }
}

private struct DisposableFileSystemFixture {
  let rootURL: URL

  init() throws {
    rootURL = FileManager.default.temporaryDirectory
      .appending(
        path: "CrazyFileManagerScannerTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(
      at: rootURL,
      withIntermediateDirectories: true
    )
  }

  func write(bytes: [UInt8], to relativePath: String) throws {
    try Data(bytes).write(
      to: rootURL.appending(path: relativePath, directoryHint: .notDirectory),
      options: .atomic
    )
  }

  func createDirectory(_ relativePath: String) throws {
    try FileManager.default.createDirectory(
      at: rootURL.appending(path: relativePath, directoryHint: .isDirectory),
      withIntermediateDirectories: true
    )
  }

  func createSymbolicLink(
    _ relativePath: String,
    destination: String
  ) throws {
    try FileManager.default.createSymbolicLink(
      at: rootURL.appending(path: relativePath, directoryHint: .notDirectory),
      withDestinationURL: rootURL.appending(
        path: destination,
        directoryHint: .isDirectory
      )
    )
  }

  func createHardLink(
    _ relativePath: String,
    source: String
  ) throws {
    try FileManager.default.linkItem(
      at: rootURL.appending(path: source, directoryHint: .notDirectory),
      to: rootURL.appending(path: relativePath, directoryHint: .notDirectory)
    )
  }

  func collectItems(
    from scanner: FoundationFileSystemScanner
  ) async throws -> [ScannedItem] {
    let batches = await scanner.batches(for: .homeFolder(rootURL))
    var items: [ScannedItem] = []
    for try await batch in batches {
      items.append(contentsOf: batch.items)
    }
    return items
  }

  func remove() throws {
    try FileManager.default.removeItem(at: rootURL)
  }
}
