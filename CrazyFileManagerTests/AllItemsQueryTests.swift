import Foundation
import Testing

@testable import CrazyFileManager

@Suite("All Items Query")
struct AllItemsQueryTests {
  @Test
  func givenItemsOfDifferentKinds_whenQueryFiltersByKind_thenOnlyMatchingKindRemains() {
    let file = AllItemsQueryTests.item(name: "file.bin", kind: .file, diskUsedBytes: 10)
    let folder = AllItemsQueryTests.item(name: "Folder", kind: .folder, diskUsedBytes: 20)
    var query = AllItemsQuery()
    query.filters.kinds = [.folder]

    let result = query.applying(to: [file, folder])

    #expect(result.map(\.name) == ["Folder"])
  }

  @Test
  func givenMultipleFilterDimensions_whenQueryApplies_thenOnlyItemsMatchingAllApply() {
    let visibleSmall = AllItemsQueryTests.item(
      name: "visible-small.bin",
      diskUsedBytes: 5,
      isHidden: false
    )
    let hiddenSmall = AllItemsQueryTests.item(
      name: ".hidden-small.bin",
      diskUsedBytes: 5,
      isHidden: true
    )
    let hiddenLarge = AllItemsQueryTests.item(
      name: ".hidden-large.bin",
      diskUsedBytes: 50,
      isHidden: true
    )
    var query = AllItemsQuery()
    query.filters.hidden = .onlyTrue
    query.filters.minimumDiskUsedBytes = 10

    let result = query.applying(to: [visibleSmall, hiddenSmall, hiddenLarge])

    #expect(result.map(\.name) == [".hidden-large.bin"])
  }

  @Test
  func givenASearchTerm_whenQueryApplies_thenNameAndPathMatchesAreFound() {
    let byName = AllItemsQueryTests.item(name: "alpha.bin", diskUsedBytes: 10)
    let unrelated = AllItemsQueryTests.item(name: "beta.bin", diskUsedBytes: 10)
    var query = AllItemsQuery()
    query.searchText = "alpha"

    let result = query.applying(to: [byName, unrelated])

    #expect(result.map(\.name) == ["alpha.bin"])
  }

  @Test
  func givenItemsWithDistinctNames_whenSortedByNameInBothDirections_thenOrderMatches() {
    let alpha = AllItemsQueryTests.item(name: "alpha.bin", diskUsedBytes: 10)
    let beta = AllItemsQueryTests.item(name: "beta.bin", diskUsedBytes: 20)
    var ascending = AllItemsQuery()
    ascending.sort = AllItemsSort(field: .name, direction: .ascending)
    var descending = AllItemsQuery()
    descending.sort = AllItemsSort(field: .name, direction: .descending)

    #expect(ascending.applying(to: [beta, alpha]).map(\.name) == ["alpha.bin", "beta.bin"])
    #expect(descending.applying(to: [alpha, beta]).map(\.name) == ["beta.bin", "alpha.bin"])
  }

  private static func item(
    name: String,
    kind: StorageItemKind = .file,
    diskUsedBytes: Int64?,
    isHidden: Bool = false
  ) -> StorageTreeItem {
    StorageTreeItem(
      id: UUID(),
      parentID: nil,
      location: URL(fileURLWithPath: "/Users/tester").appending(path: name),
      name: name,
      kind: kind,
      diskUsedBytes: diskUsedBytes,
      apparentSizeBytes: diskUsedBytes,
      isDiskUsedIncomplete: false,
      isApparentSizeIncomplete: false,
      hasChildren: false,
      isRoot: false,
      isHidden: isHidden
    )
  }
}
