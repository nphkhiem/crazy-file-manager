import Foundation

enum AllItemsSortField: Equatable, Sendable {
  case diskUsed
  case apparentSize
  case name
  case modifiedAt
  case path
}

enum SortDirection: Equatable, Sendable {
  case ascending
  case descending
}

struct AllItemsSort: Equatable, Sendable {
  var field: AllItemsSortField = .diskUsed
  var direction: SortDirection = .descending
}

enum TriStateFilter: Equatable, Sendable {
  case any
  case onlyTrue
  case onlyFalse
}

struct AllItemsFilters: Equatable, Sendable {
  var kinds: Set<StorageItemKind> = []
  var hidden: TriStateFilter = .any
  var cloudOnly: TriStateFilter = .any
  var minimumDiskUsedBytes: Int64?
}

struct AllItemsQuery: Equatable, Sendable {
  var searchText: String = ""
  var filters: AllItemsFilters = AllItemsFilters()
  var sort: AllItemsSort = AllItemsSort()
}

struct AllItemsPage: Equatable, Sendable {
  let items: [StorageTreeItem]
  let nextOffset: Int?
}
