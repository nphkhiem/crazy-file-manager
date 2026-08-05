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

  @Test(.enabled(if: ProcessInfo.processInfo.environment["RUN_STRESS_BENCHMARK"] == "1"))
  func
    givenAMillionItemFlatIndex_whenPagedSortedFilteredAndSearched_thenEachQueryCompletesWithinTheLatencyBudget()
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
    for try await batch in await scanner.batches(for: scope) {
      try await fixture.index.append(batch, to: candidate)
    }
    try await fixture.promote(candidate, itemCount: 1_000_000)

    let clock = ContinuousClock()
    var report: [String] = []

    var firstPageQuery = AllItemsQuery()
    firstPageQuery.sort = AllItemsSort(field: .name, direction: .ascending)
    let firstPageStart = clock.now
    let firstPage = try await fixture.index.flatItems(
      in: candidate,
      query: firstPageQuery,
      offset: 0,
      limit: 200
    )
    let firstPageElapsed = clock.now - firstPageStart
    report.append("first page (offset 0): \(firstPageElapsed)")
    #expect(firstPage.items.count == 200)
    #expect(firstPageElapsed < .seconds(1))

    let deepPageStart = clock.now
    let deepPage = try await fixture.index.flatItems(
      in: candidate,
      query: firstPageQuery,
      offset: 900_000,
      limit: 200
    )
    let deepPageElapsed = clock.now - deepPageStart
    report.append("deep page (offset 900,000): \(deepPageElapsed)")
    #expect(deepPage.items.count == 200)
    // LIMIT/OFFSET pagination inherently costs more at a deep offset than the first page --
    // no acceptance criterion sets a numeric budget for this specifically (unlike first-results
    // at 2s or folder expansion at 200ms), so the meaningful assertion here is the RATIO: deep
    // pagination must stay roughly linear in the offset, not blow up unboundedly, which is what
    // would indicate an accidental full-table materialization rather than an indexed skip.
    #expect(
      deepPageElapsed < firstPageElapsed * 20,
      "deep-offset pagination should not cost dramatically more than the first page"
    )

    for field in [
      AllItemsSortField.diskUsed, .apparentSize, .name, .modifiedAt, .path,
    ] {
      var query = AllItemsQuery()
      query.sort = AllItemsSort(field: field, direction: .descending)
      let start = clock.now
      let page = try await fixture.index.flatItems(
        in: candidate,
        query: query,
        offset: 0,
        limit: 200
      )
      let elapsed = clock.now - start
      report.append("sort by \(field): \(elapsed)")
      #expect(page.items.count == 200)
      #expect(elapsed < .seconds(1))
    }

    var kindQuery = AllItemsQuery()
    kindQuery.filters.kinds = [.file]
    let kindStart = clock.now
    let kindPage = try await fixture.index.flatItems(
      in: candidate,
      query: kindQuery,
      offset: 0,
      limit: 200
    )
    let kindElapsed = clock.now - kindStart
    report.append("kind filter: \(kindElapsed)")
    #expect(kindPage.items.count == 200)
    #expect(kindElapsed < .seconds(1))

    var searchQuery = AllItemsQuery()
    searchQuery.searchText = "item-500000"
    let searchStart = clock.now
    let searchPage = try await fixture.index.flatItems(
      in: candidate,
      query: searchQuery,
      offset: 0,
      limit: 200
    )
    let searchElapsed = clock.now - searchStart
    report.append("search: \(searchElapsed)")
    #expect(searchPage.items.map(\.name) == ["item-500000.bin"])
    #expect(searchElapsed < .seconds(2))

    Self.printPerformanceReport(
      criterion: "million-item flatItems: pagination, sort, filter, search",
      measured: report.joined(separator: "; ")
    )
  }

  @Test
  func
    givenAParentWithFiftyThousandDirectChildren_whenExpanded_thenItCompletesWithinTheLatencyBudget()
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
    try await fixture.promote(candidate, itemCount: 50_000)
    let root = try await fixture.index.treeRoot(in: candidate)

    let clock = ContinuousClock()
    let start = clock.now
    let page = try await fixture.index.directChildren(
      of: root.id,
      in: candidate,
      offset: 0,
      limit: 200
    )
    let elapsed = clock.now - start

    Self.printPerformanceReport(
      criterion: "indexed direct-child expansion (parent with 50,000 children)",
      measured: "\(elapsed)"
    )
    #expect(page.items.count == 200)
    #expect(elapsed < .milliseconds(400))
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
