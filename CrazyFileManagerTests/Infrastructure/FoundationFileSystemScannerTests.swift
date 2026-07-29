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
