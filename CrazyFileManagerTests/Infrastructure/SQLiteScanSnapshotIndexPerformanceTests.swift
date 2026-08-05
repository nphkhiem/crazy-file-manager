import Foundation
import Testing

@testable import CrazyFileManager

@Suite("SQLite Scan Snapshot Index Performance")
struct SQLiteScanSnapshotIndexPerformanceTests {
  @Test
  func
    givenATenThousandItemSyntheticScan_whenScannedAndPromoted_thenMemoryStaysWithinTheSmokeBound()
    async throws
  {
    let fixture = try TemporarySnapshotIndexFixture()
    defer { try? fixture.remove() }
    let scope = ScanScope.homeFolder(fixture.scopeURL)
    let scanner = SyntheticFileSystemScanner(totalItemCount: 10_000, scopeURL: fixture.scopeURL)
    let baseline = ProcessMemoryProbe.currentResidentBytes()

    let candidate = try await fixture.index.beginCandidate(for: scope)
    for try await batch in await scanner.batches(for: scope) {
      try await fixture.index.append(batch, to: candidate)
    }
    try await fixture.promote(candidate, itemCount: 10_000)

    let peak = ProcessMemoryProbe.currentResidentBytes()
    let deltaBytes = peak - baseline
    Self.printPerformanceReport(
      criterion: "smoke scan-and-promote memory (10,000 items)",
      measured: "\(deltaBytes / 1_000_000) MB delta"
    )
    #expect(deltaBytes < 100_000_000)
  }

  @Test
  func givenAFiftyThousandItemSyntheticScan_whenPromoted_thenParentResolutionCompletesQuickly()
    async throws
  {
    let fixture = try TemporarySnapshotIndexFixture()
    defer { try? fixture.remove() }
    let scope = ScanScope.homeFolder(fixture.scopeURL)
    let scanner = SyntheticFileSystemScanner(totalItemCount: 50_000, scopeURL: fixture.scopeURL)
    let candidate = try await fixture.index.beginCandidate(for: scope)
    for try await batch in await scanner.batches(for: scope) {
      try await fixture.index.append(batch, to: candidate)
    }

    let clock = ContinuousClock()
    let start = clock.now
    try await fixture.promote(candidate, itemCount: 50_000)
    let elapsed = clock.now - start

    Self.printPerformanceReport(
      criterion: "promoteCandidate parent resolution (50,000 items)",
      measured: "\(elapsed)"
    )
    #expect(elapsed < .seconds(10))
  }

  @Test
  func givenALargeSyntheticScan_whenTheFirstBatchArrives_thenItArrivesWellWithinTheLatencyBudget()
    async throws
  {
    let fixture = try TemporarySnapshotIndexFixture()
    defer { try? fixture.remove() }
    let scope = ScanScope.homeFolder(fixture.scopeURL)
    let scanner = SyntheticFileSystemScanner(
      totalItemCount: 1_000_000,
      scopeURL: fixture.scopeURL
    )
    let candidate = try await fixture.index.beginCandidate(for: scope)

    let clock = ContinuousClock()
    let start = clock.now
    var iterator = await scanner.batches(for: scope).makeAsyncIterator()
    let firstBatch = try await iterator.next()
    try await fixture.index.append(try #require(firstBatch), to: candidate)
    let elapsed = clock.now - start

    Self.printPerformanceReport(
      criterion: "first-batch latency (from a 1,000,000-item synthetic source)",
      measured: "\(elapsed)"
    )
    #expect(elapsed < .seconds(2))
  }

  @Test(.enabled(if: ProcessInfo.processInfo.environment["RUN_STRESS_BENCHMARK"] == "1"))
  func
    givenAOneMillionItemSyntheticScan_whenScannedAndPromoted_thenPeakMemoryStaysBelowTheSpecBound()
    async throws
  {
    let fixture = try TemporarySnapshotIndexFixture()
    defer { try? fixture.remove() }
    let scope = ScanScope.homeFolder(fixture.scopeURL)
    let scanner = SyntheticFileSystemScanner(
      totalItemCount: 1_000_000,
      scopeURL: fixture.scopeURL
    )
    let baseline = ProcessMemoryProbe.currentResidentBytes()

    let candidate = try await fixture.index.beginCandidate(for: scope)
    for try await batch in await scanner.batches(for: scope) {
      try await fixture.index.append(batch, to: candidate)
    }
    try await fixture.promote(candidate, itemCount: 1_000_000)

    let peak = ProcessMemoryProbe.currentResidentBytes()
    let deltaBytes = peak - baseline
    Self.printPerformanceReport(
      criterion: "one-million-item scan-and-promote memory",
      measured: "\(deltaBytes / 1_000_000) MB delta"
    )
    #expect(deltaBytes < 500_000_000)
  }

  @Test(.enabled(if: ProcessInfo.processInfo.environment["RUN_STRESS_BENCHMARK"] == "1"))
  func givenAFiveMillionItemSyntheticScan_whenScannedAndPromoted_thenItCompletesWithoutCrashing()
    async throws
  {
    let fixture = try TemporarySnapshotIndexFixture()
    defer { try? fixture.remove() }
    let scope = ScanScope.homeFolder(fixture.scopeURL)
    let scanner = SyntheticFileSystemScanner(
      totalItemCount: 5_000_000,
      scopeURL: fixture.scopeURL
    )
    let baseline = ProcessMemoryProbe.currentResidentBytes()

    let clock = ContinuousClock()
    let start = clock.now
    let candidate = try await fixture.index.beginCandidate(for: scope)
    for try await batch in await scanner.batches(for: scope) {
      try await fixture.index.append(batch, to: candidate)
    }
    try await fixture.promote(candidate, itemCount: 5_000_000)
    let elapsed = clock.now - start

    let peak = ProcessMemoryProbe.currentResidentBytes()
    Self.printPerformanceReport(
      criterion: "five-million-item stress scan-and-promote",
      measured: "completed in \(elapsed), \((peak - baseline) / 1_000_000) MB delta"
    )
  }

  private static func printPerformanceReport(criterion: String, measured: String) {
    var cpuBrand = [CChar](repeating: 0, count: 256)
    var cpuBrandSize = cpuBrand.count
    sysctlbyname("machdep.cpu.brand_string", &cpuBrand, &cpuBrandSize, nil, 0)
    let cpuDescription = cpuBrand.withUnsafeBufferPointer { buffer in
      String(cString: buffer.baseAddress!)
    }
    let physicalMemoryGB = Double(ProcessInfo.processInfo.physicalMemory) / 1_000_000_000
    print(
      """
      [performance] \(criterion)
        hardware: \(cpuDescription), \(physicalMemoryGB) GB RAM, \
      macOS \(ProcessInfo.processInfo.operatingSystemVersionString)
        measured: \(measured)
      """
    )
  }
}
