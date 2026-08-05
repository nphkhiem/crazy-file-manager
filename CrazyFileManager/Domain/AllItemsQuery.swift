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

extension AllItemsQuery {
  func applying(to items: [StorageTreeItem]) -> [StorageTreeItem] {
    let normalizedSearchText = searchText.lowercased()
    return
      items
      .filter { item in
        if !filters.kinds.isEmpty, !filters.kinds.contains(item.kind) {
          return false
        }
        switch filters.hidden {
        case .any: break
        case .onlyTrue: if !item.isHidden { return false }
        case .onlyFalse: if item.isHidden { return false }
        }
        switch filters.cloudOnly {
        case .any: break
        case .onlyTrue: if !item.isCloudOnly { return false }
        case .onlyFalse: if item.isCloudOnly { return false }
        }
        if let minimum = filters.minimumDiskUsedBytes, (item.diskUsedBytes ?? -1) < minimum {
          return false
        }
        if !normalizedSearchText.isEmpty {
          let name = item.name.lowercased()
          let path = item.location.path(percentEncoded: false).lowercased()
          if !name.contains(normalizedSearchText), !path.contains(normalizedSearchText) {
            return false
          }
        }
        return true
      }
      .sorted { Self.sortsBefore($0, $1, sort: sort) }
  }

  private static func sortsBefore(
    _ lhs: StorageTreeItem,
    _ rhs: StorageTreeItem,
    sort: AllItemsSort
  ) -> Bool {
    func compare<Value: Comparable>(_ lhsValue: Value?, _ rhsValue: Value?) -> Bool? {
      switch (lhsValue, rhsValue) {
      case (.some(let a), .some(let b)):
        guard a != b else { return nil }
        return sort.direction == .ascending ? a < b : a > b
      case (.some, .none):
        return true
      case (.none, .some):
        return false
      case (.none, .none):
        return nil
      }
    }

    let primary: Bool?
    switch sort.field {
    case .diskUsed:
      primary = compare(lhs.diskUsedBytes, rhs.diskUsedBytes)
    case .apparentSize:
      primary = compare(lhs.apparentSizeBytes, rhs.apparentSizeBytes)
    case .name:
      primary = compare(lhs.name, rhs.name)
    case .modifiedAt:
      primary = compare(lhs.modifiedAt, rhs.modifiedAt)
    case .path:
      primary = compare(
        lhs.location.path(percentEncoded: false),
        rhs.location.path(percentEncoded: false)
      )
    }
    if let primary {
      return primary
    }
    return lhs.id.uuidString < rhs.id.uuidString
  }
}
