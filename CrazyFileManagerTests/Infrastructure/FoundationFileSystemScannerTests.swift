import Foundation
import Testing

@testable import CrazyFileManager

@Suite("Foundation File System Scanner")
struct FoundationFileSystemScannerTests {
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
  func givenSymbolicLinkToDirectory_whenScopeIsScanned_thenLinkIsIncludedWithoutTraversingTarget()
    async throws
  {
    let fixture = try DisposableFileSystemFixture()
    defer { try? fixture.remove() }
    try fixture.createDirectory("target")
    try fixture.write(bytes: [0x01], to: "target/inside.bin")
    try fixture.createSymbolicLink("link", destination: "target")
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
}

private struct StubCloudMetadataReader: CloudMetadataReading {
  enum ReadError: Error {
    case unavailable
  }

  let cloudOnlyNames: Set<String>
  let unavailableNames: Set<String>

  func isCloudOnly(at url: URL) throws -> Bool {
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
