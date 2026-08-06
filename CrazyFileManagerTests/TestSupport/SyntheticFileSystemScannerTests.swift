import Foundation
import Testing

@testable import CrazyFileManager

@Suite("Synthetic File System Scanner")
struct SyntheticFileSystemScannerTests {
  @Test
  func givenALargeItemCount_whenTheStreamIsNeverConsumed_thenNoItemsAreGeneratedYet() async throws {
    let scanner = SyntheticFileSystemScanner(
      totalItemCount: 5_000_000,
      scopeURL: URL(filePath: "/synthetic", directoryHint: .isDirectory)
    )

    _ = await scanner.batches(for: SyntheticFileSystemScannerTests.scope())

    #expect(await scanner.generatedItemCount == 0)
  }

  @Test
  func givenALargeItemCount_whenOneBatchIsPulled_thenExactlyOneBatchWorthIsGenerated() async throws
  {
    let scanner = SyntheticFileSystemScanner(
      totalItemCount: 5_000_000,
      scopeURL: URL(filePath: "/synthetic", directoryHint: .isDirectory)
    )

    var iterator = await scanner.batches(for: SyntheticFileSystemScannerTests.scope())
      .makeAsyncIterator()
    _ = try await iterator.next()

    #expect(await scanner.generatedItemCount == 128)
  }

  @Test
  func givenExactlyOneBatchWorthOfItems_whenGenerated_thenTheBatchShapeMatchesTheRealScanner()
    async throws
  {
    let scanner = SyntheticFileSystemScanner(
      totalItemCount: 128,
      scopeURL: URL(filePath: "/synthetic", directoryHint: .isDirectory)
    )
    var iterator = await scanner.batches(for: SyntheticFileSystemScannerTests.scope())
      .makeAsyncIterator()

    let firstBatch = try await iterator.next()
    let secondBatch = try await iterator.next()

    let batch = try #require(firstBatch)
    #expect(batch.items.count == 128)
    #expect(batch.issues.isEmpty)
    #expect(batch.progress.discoveredItemCount == 128)
    #expect(batch.progress.issueCount == 0)
    #expect(secondBatch == nil)
  }

  private static func scope() -> ScanScope {
    ScanScope(
      kind: .custom,
      location: URL(filePath: "/synthetic", directoryHint: .isDirectory),
      volumeIdentity: ScanVolumeIdentity(rawValue: "synthetic-volume"),
      volumeCharacteristics: ScanVolumeCharacteristics(
        isInternal: true,
        isReadOnly: false,
        isRemovable: false
      )
    )
  }
}
